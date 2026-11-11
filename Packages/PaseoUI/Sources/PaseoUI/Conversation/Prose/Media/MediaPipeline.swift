#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import UIKit

// MARK: - Results

/// A decoded image and the shape it wants to be laid out in.
///
/// A class, not a struct, for two reasons: `NSCache` stores objects, and the payload crosses
/// from the decode task to the main actor. `UIImage` is immutable and safe to hand around;
/// `@unchecked Sendable` states that in one place instead of at every call site.
final class MediaPayload: @unchecked Sendable {
    let image: UIImage
    /// Width / height as decoded, so a card can reserve its box before the pixels land and
    /// never shift what is above or below it.
    let aspectRatio: CGFloat

    init(image: UIImage, aspectRatio: CGFloat) {
        self.image = image
        self.aspectRatio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
    }
}

/// A remembered failure and when it happened. `NSCache` stores objects and the card's first
/// body pass must be able to ask "did this URL fail a moment ago?" without an actor hop, so the
/// memo lives outside the actor like the decoded image does.
final class MediaFailureMemo: @unchecked Sendable {
    let failure: MediaFailure
    let at: Date

    init(failure: MediaFailure, at: Date) {
        self.failure = failure
        self.at = at
    }
}

/// Why media did not load, phrased for the card (H5 §3: honest and useful).
enum MediaFailure: Error, Equatable, Sendable {
    case badURL
    case unsupportedScheme(String)
    case notAnImage(contentType: String?)
    case http(Int)
    case offline
    case timedOut
    /// Over a wire cap (`mediaDownloadCap`) or the hard ceiling. Carries the bytes learned
    /// so the card's tap-to-download box can show the size.
    case tooLarge(bytes: Int64?)
    case decoding
    case other

    /// One line, sentence case, no jargon the user can't act on.
    var message: String {
        switch self {
        case .badURL: "The link isn't a valid address"
        case .unsupportedScheme: "This kind of link can't be loaded"
        case .notAnImage(let contentType):
            contentType?.hasPrefix("text/html") == true
                ? "The link opened a web page, not an image" : "The link isn't an image"
        case .http(404): "The page is gone (404)"
        case .http(403): "The server refused (403)"
        case .http(let code): "The server said \(code)"
        case .offline: "No connection"
        case .timedOut: "The server didn't answer"
        case .tooLarge: "The image is too large"
        case .decoding: "The image couldn't be read"
        case .other: "The download failed"
        }
    }
}

enum MediaOutcome: Sendable {
    case image(MediaPayload)
    /// An SVG: the caller renders it through the shared offscreen snapshot renderer, which
    /// needs a width, the colour scheme and the main actor.
    case svg(source: String, aspectRatio: CGFloat?)
    case failure(MediaFailure)
}

/// One step of a streaming load. Size arrives first — often long before the download
/// finishes — so the card settles to its true ratio once, early, and never jumps again.
enum MediaEvent: Sendable {
    /// The true size, from the incremental probe (remote) or the header decode (daemon).
    case size(CGSize)
    /// 0…1 by 10 % buckets, only when the total is known. O(10) events per download, never
    /// per chunk: the progress ring moves without re-rendering the card per packet.
    case progress(Double)
    case final(MediaOutcome)
}

// MARK: - Sources

/// A daemon file, by location. `workspaceID` is agent-scoped and daemon-generated, so it
/// scopes the cache to one workspace on one host the way the ticket's `host+cwd+path`
/// identity does; `revision`, when the daemon sent it, versions the disk entry so an edited
/// file refreshes instead of serving the old bytes.
struct DaemonFileRef: Hashable, Sendable {
    var workspaceID: String
    var path: String
    var revision: String?
}

/// Where the pixels come from. One pipeline, two sources — there are never two loaders.
enum MediaSource: Hashable, Sendable {
    case remote(URL)
    case daemon(DaemonFileRef)
}

/// Raw daemon bytes plus the revision the daemon reported, if any. The controller builds
/// this from `checkout.files.fetch(path, maxBytes:)`; the pipeline owns everything after.
struct DaemonFileBytes: Sendable {
    var data: Data
    var revision: String?
}

// MARK: - Sizing

enum MediaSizing {
    /// The pixel width to decode at: the card's width in points × the screen scale, rounded up
    /// to a 128 px bucket so a one-point layout change does not throw the decode away.
    static func pixelWidth(points: CGFloat, scale: CGFloat) -> Int {
        guard points > 1, scale > 0 else { return 640 }
        let pixels = points * scale
        let bucket = (pixels / 128).rounded(.up) * 128
        return Int(min(max(bucket, 128), 2048))
    }
}

// MARK: - Pipeline

/// The one media path for the whole app (G2 §4.1), evolved from `RemoteImageLoader`.
///
/// Every H5 behaviour is kept: the shared session (sized `URLCache`, `Paseo/<version>`
/// User-Agent, timeouts), in-flight de-duplication, the three bounded caches, the failure
/// taxonomy and TTL, SVG routing (content type, `.svg` hint, markup sniff, `data:` URLs),
/// the width-exact off-main decode, and the rule that a load started for a card that scrolled
/// away is *not* cancelled — it finishes, fills the cache, and is instant on return.
///
/// What G2 adds:
/// - an incremental size probe (`CGImageSourceCreateIncremental` fed by a streaming data
///   task) that publishes the true size **before** the download finishes;
/// - the daemon-file source (`FileExplorerRequest(mode: .file, acceptBinary: true, maxBytes:
///   64 MB)` behind `daemonFetch`), cached on disk in `Caches/daemon-media/<sha256>`, LRU
///   at 500 MB;
/// - the streaming event shape (`size` → `progress` → `final`), shared per key so adjacent
///   cards never download the same bytes twice;
/// - the in-flight ceiling (`capBytes`, from `mediaDownloadCap`): past it the stream aborts
///   and the card flips to tap-to-download with the learned size;
/// - a memory-warning purge of the decoded cache.
actor MediaPipeline {
    static let shared = MediaPipeline()

    /// ~64 decoded images or 48 MB, whichever comes first. Past that the oldest are a scroll
    /// away from being refetched from `URLCache`, which is cheaper than starving the app.
    private static let imageCacheCountLimit = 64
    private static let imageCacheCostLimit = 48 * 1024 * 1024
    /// A remote image is at most this big on the wire; anything larger is a file, not a chat image.
    static let maxBytes = 20 * 1024 * 1024
    /// Daemon files cap where the socket read does (G10 owns the row past it).
    static let maxDaemonBytes: Int64 = 64 * 1024 * 1024
    /// SVGs are markup and are rendered as a document; a screenshot-sized drawing fits easily.
    static let maxSVGBytes = 2 * 1024 * 1024
    /// How long a failure is remembered, so scrolling over a dead link does not refetch it.
    private static let failureTTL: TimeInterval = 60
    /// Daemon bytes on disk, bounded and least-recently-used.
    static let diskBudget: Int64 = 500 * 1024 * 1024

    /// `NSCache` is documented thread-safe; `nonisolated(unsafe)` says so to the compiler and
    /// lets the card's first frame read it without an actor hop.
    nonisolated(unsafe) private static let decoded = NSCache<NSString, MediaPayload>()
    /// Recent failures, by URL and by URL + pixel bucket. Bounded and time-limited; `Retry`
    /// bypasses it. Readable from the card's first frame, so a card that failed last time comes
    /// back as the compact failure row instead of flashing a placeholder first.
    nonisolated(unsafe) private static let failures = NSCache<NSString, MediaFailureMemo>()

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            .map { $0.appending(path: "RemoteImages", directoryHint: .isDirectory) }
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024, directory: directory)
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent()]
        return URLSession(configuration: configuration)
    }()

    /// One flight per (source, pixel bucket): every card showing the same bytes shares it.
    private struct Flight {
        /// Continuations currently watching, by subscription.
        var watchers: [UUID: AsyncStream<MediaEvent>.Continuation] = [:]
        /// The last progress bucket emitted (10 % steps), so the ring moves O(10) times.
        var lastBucket = -1
    }

    private var flights: [String: Flight] = [:]
    /// The daemon read, set once by the conversation controller. Nil outside a conversation
    /// (previews never render daemon files — the card gates on `RichActions` first, so the
    /// driver treats a missing hook as unreachable and fails closed).
    /// Nil means unreachable (a preview): the driver fails closed with `.other`.
    private var daemonFetch: (@Sendable (DaemonFileRef) async -> DaemonFileBytes?)?

    init() {
        Self.decoded.countLimit = Self.imageCacheCountLimit
        Self.decoded.totalCostLimit = Self.imageCacheCostLimit
        Self.failures.countLimit = 32
        // The shared instance lives for the app's life; one observer, no token to drop.
        // `NSCache` already evicts under pressure — this just drops decoded bitmaps first,
        // while sizes (cheap) and failures stay.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { _ in
            MediaPipeline.decoded.removeAllObjects()
        }
    }

    /// Sets the daemon read. Called once per conversation controller, with a stable closure.
    func setDaemonFetch(_ fetch: (@Sendable (DaemonFileRef) async -> DaemonFileBytes?)?) {
        daemonFetch = fetch
    }

    /// The app's identity on the wire. Wikimedia answers **403** to a request with no
    /// User-Agent at all (checked with `curl` against `upload.wikimedia.org`); a stable,
    /// generic app UA is the polite answer everywhere else. No user data, no device name.
    static func userAgent() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "Paseo/\(version ?? "0") (iOS)"
    }

    // MARK: First frame (synchronous, no hop)

    /// The cache identity of a URL: the normalized absolute string, so a card's first-frame
    /// lookup and the loader's writes agree even when the source needed encoding.
    static func cacheIdentity(for urlString: String) -> String {
        target(for: urlString)?.absoluteString ?? urlString
    }

    /// What we already hold for a key, for the card's very first body pass. An `NSCache`
    /// read is O(1) and thread-safe, so scrolling back draws the image on the first frame
    /// instead of a placeholder that flashes out one runloop later.
    static func cached(for key: String) -> MediaPayload? {
        decoded.object(forKey: key as NSString)
    }

    /// A failure this key is still remembered for, or nil when it is unknown or expired.
    static func cachedFailure(for key: String) -> MediaFailure? {
        guard let memo = failures.object(forKey: key as NSString),
            Date().timeIntervalSince(memo.at) < failureTTL
        else { return nil }
        return memo.failure
    }

    // MARK: Streaming loads

    /// Streams one load: the true size as soon as the probe learns it, progress by 10 %
    /// buckets while the total is known, then the final outcome. Cards showing the same bytes
    /// share the flight; a card that scrolled away detaches without cancelling the driver,
    /// which finishes into the cache for its return.
    ///
    /// - `capBytes`: the in-flight ceiling from `mediaDownloadCap`. Past it the stream ends
    ///   in `.failure(.tooLarge)` and the card offers tap-to-download. Nil disables the
    ///   ceiling (an explicit user tap, or a caller with no policy context).
    /// - `ignoreFailureCache`: a Retry/extraordinary reload bypasses the failure memo.
    func events(
        source: MediaSource, pixelWidth: Int, capBytes: Int64? = nil,
        ignoreFailureCache: Bool = false
    ) async -> AsyncStream<MediaEvent> {
        let key = streamKey(source: source, pixelWidth: pixelWidth)
        let identity = identityKey(source: source)

        // The same picture at another bucket (a rotation, a sheet): right for the first
        // paint, and the exact size follows if it is asked for again.
        if let hit = Self.decoded.object(forKey: key as NSString) {
            return Self.single(.final(.image(hit)))
        }
        if let hit = Self.decoded.object(forKey: identity as NSString) {
            Self.decoded.setObject(hit, forKey: key as NSString, cost: 0)
            return Self.single(.final(.image(hit)))
        }
        if !ignoreFailureCache {
            if let failure = Self.cachedFailure(for: key) {
                return Self.single(.final(.failure(failure)))
            }
            if let failure = Self.cachedFailure(for: identity) {
                return Self.single(.final(.failure(failure)))
            }
        }
        // An SVG-ish or data: source resolves without the network; the daemon path resolves
        // through its own fetch. Only http(s) streams below.
        if case .remote(let url) = source, url.scheme?.lowercased() == "data" {
            return await Self.single(decodeDataURL(url, pixelWidth: pixelWidth))
        }
        if case .remote(let url) = source, url.scheme?.lowercased() == "blob" {
            // A blob handle only means something inside the browser that made it.
            return Self.single(.final(.failure(.unsupportedScheme("blob"))))
        }

        let (stream, continuation) = AsyncStream<MediaEvent>.makeStream()
        let id = UUID()
        continuation.onTermination = { _ in
            Task { await MediaPipeline.shared.detach(id: id, key: key) }
        }
        // Sharing subsumes the old in-flight cap: one flight per (content, bucket) however
        // many cards watch it, and the entry is dropped when the driver reports. Distinct
        // content still downloads concurrently (per-host connection limits apply).
        var flight = flights[key] ?? Flight()
        let isNew = flights[key] == nil
        flight.watchers[id] = continuation
        flights[key] = flight
        if isNew {
            Task.detached { [source, pixelWidth, key, capBytes] in
                await MediaPipeline.drive(
                    source: source, pixelWidth: pixelWidth, key: key, capBytes: capBytes)
            }
        }
        if let aspect = MediaMetadataCache.aspectRatio(for: identity) {
            continuation.yield(.size(CGSize(width: aspect, height: 1)))
        }
        return stream
    }

    /// The classic one-shot: the final outcome, for callers with no streaming UI (YouTube
    /// stills, the viewer's fallback fetch).
    func load(
        source: MediaSource, pixelWidth: Int, ignoreFailureCache: Bool = false
    ) async -> MediaOutcome {
        for await event in await events(
            source: source, pixelWidth: pixelWidth, ignoreFailureCache: ignoreFailureCache
        ) {
            if case .final(let outcome) = event { return outcome }
        }
        return .failure(.other)
    }

    /// Compatibility for remote-URL callers: `http(s)` streams, `data:` decodes inline,
    /// anything else fails closed exactly as before.
    func load(
        urlString: String, pixelWidth: Int, ignoreFailureCache: Bool = false
    ) async -> MediaOutcome {
        guard let target = Self.target(for: urlString) else { return .failure(.badURL) }
        return await load(
            source: .remote(target), pixelWidth: pixelWidth,
            ignoreFailureCache: ignoreFailureCache)
    }

    // MARK: Flight plumbing (actor-isolated)

    private static func single(_ event: MediaEvent) -> AsyncStream<MediaEvent> {
        AsyncStream { continuation in
            continuation.yield(event)
            continuation.finish()
        }
    }

    private func detach(id: UUID, key: String) {
        guard var flight = flights[key] else { return }
        flight.watchers.removeValue(forKey: id)
        // The driver is deliberately *not* cancelled: it finishes into the cache (H5) and the
        // empty flight entry is dropped when it reports.
        flights[key] = flight
    }

    private func reportSize(key: String, aspect: CGFloat, identity: String) {
        MediaMetadataCache.remember(aspect, for: identity)
        guard aspect.isFinite, aspect > 0, let flight = flights[key] else { return }
        let event = MediaEvent.size(CGSize(width: aspect, height: 1))
        for continuation in flight.watchers.values { continuation.yield(event) }
    }

    private func reportProgress(key: String, fraction: Double) {
        guard var flight = flights[key] else { return }
        let bucket = Int((fraction * 10).rounded(.down))
        guard bucket != flight.lastBucket else { return }
        flight.lastBucket = bucket
        flights[key] = flight
        for continuation in flight.watchers.values {
            continuation.yield(.progress(min(max(fraction, 0), 1)))
        }
    }

    private func reportFinal(key: String, identity: String, outcome: MediaOutcome) {
        let flight = flights.removeValue(forKey: key)
        switch outcome {
        case .image(let payload):
            Self.decoded.setObject(
                payload, forKey: key as NSString, cost: Self.cost(of: payload))
            Self.decoded.setObject(payload, forKey: identity as NSString, cost: 0)
            MediaMetadataCache.remember(payload.aspectRatio, for: identity)
            Self.forgetFailure(key)
            Self.forgetFailure(identity)
        case .failure(let failure):
            let memo = MediaFailureMemo(failure: failure, at: Date())
            Self.failures.setObject(memo, forKey: key as NSString)
            Self.failures.setObject(memo, forKey: identity as NSString)
        case .svg:
            Self.forgetFailure(key)
            Self.forgetFailure(identity)
        }
        guard let flight else { return }
        for continuation in flight.watchers.values {
            continuation.yield(.final(outcome))
            continuation.finish()
        }
    }

    private static func forgetFailure(_ key: String) {
        failures.removeObject(forKey: key as NSString)
    }

    private static func cost(of payload: MediaPayload) -> Int {
        let width = payload.image.size.width * payload.image.scale
        let height = payload.image.size.height * payload.image.scale
        return Int(max(width, 1) * max(height, 1) * 4)
    }

    // MARK: Drivers (detached: never actor-isolated, never main)

    /// One download: stream the bytes, probe the size early, enforce the ceiling, decode at
    /// display size off main. Reports back through the actor; the actor fans out to watchers.
    private static func drive(
        source: MediaSource, pixelWidth: Int, key: String, capBytes: Int64?
    ) async {
        switch source {
        case .remote(let url):
            await driveRemote(url: url, pixelWidth: pixelWidth, key: key, capBytes: capBytes)
        case .daemon(let ref):
            await driveDaemon(ref: ref, pixelWidth: pixelWidth, key: key, capBytes: capBytes)
        }
    }

    private static func driveRemote(
        url: URL, pixelWidth: Int, key: String, capBytes: Int64?
    ) async {
        let identity = url.absoluteString
        var request = URLRequest(
            url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            // Not a child task of the caller: scrolling away does not cancel the bytes we
            // are about to want on the way back.
            (bytes, response) = try await session.bytes(for: request)
        } catch let error as URLError {
            await shared.reportFinal(key: key, identity: identity, outcome: .final(mapURLError(error)))
            return
        } catch {
            await shared.reportFinal(key: key, identity: identity, outcome: .final(.failure(.other)))
            return
        }
        let http = response as? HTTPURLResponse
        if let http, !(200..<300).contains(http.statusCode) {
            await shared.reportFinal(
                key: key, identity: identity,
                outcome: .final(.failure(.http(http.statusCode))))
            return
        }
        let contentType = http?.value(forHTTPHeaderField: "Content-Type")?.lowercased()
        let expected = response.expectedContentLength
        // The ceiling for this stream: the policy cap, inside the hard wire cap. An SVG-ish
        // response only ever needs its 2 MB.
        var ceiling = min(capBytes ?? Int64(maxBytes), Int64(maxBytes))
        if contentType?.contains("svg") == true || isSVGHint(url) {
            ceiling = min(ceiling, Int64(maxSVGBytes))
        }

        var data = Data()
        // `nil` when WebKit cannot start the source; the size events just never fire and the
        // final decode decides, exactly like a response with no size hints.
        let probe: CGImageSource? = CGImageSourceCreateIncremental(nil)
        let svgHinted = isSVGHint(url)
        var sizeSent = false
        do {
            for try await chunk in bytes {
                data.append(chunk)
                if Int64(data.count) > ceiling {
                    await shared.reportFinal(
                        key: key, identity: identity,
                        outcome: .final(.failure(.tooLarge(bytes: Int64(data.count)))))
                    return
                }
                if !sizeSent, let probe {
                    CGImageSourceUpdateData(probe, data as CFData, false)
                    if let size = incrementalSize(probe), size.height > 0 {
                        sizeSent = true
                        let aspect = size.width / size.height
                        await shared.reportSize(key: key, aspect: aspect, identity: identity)
                    } else if svgHinted, looksLikeSVG(data) {
                        // Markup, not pixels: no incremental size to learn; the viewBox
                        // parse at the end reserves the box.
                        sizeSent = true
                    }
                }
                if expected > 0 {
                    await shared.reportProgress(
                        key: key, fraction: Double(data.count) / Double(expected))
                }
            }
        } catch {
            await shared.reportFinal(key: key, identity: identity, outcome: .final(.failure(.other)))
            return
        }
        if data.count > maxBytes {
            await shared.reportFinal(
                key: key, identity: identity,
                outcome: .final(.failure(.tooLarge(bytes: Int64(data.count)))))
            return
        }
        if contentType?.contains("svg") == true || (isSVGHint(url) && looksLikeSVG(data)) {
            guard data.count <= maxSVGBytes else {
                await shared.reportFinal(
                    key: key, identity: identity,
                    outcome: .final(.failure(.tooLarge(bytes: Int64(data.count)))))
                return
            }
            guard let source = text(data), looksLikeSVG(data) else {
                await shared.reportFinal(
                    key: key, identity: identity, outcome: .final(.failure(.decoding)))
                return
            }
            let outcome = MediaOutcome.svg(
                source: source, aspectRatio: RichSVGIntrinsic.aspectRatio(of: source))
            if let aspect = RichSVGIntrinsic.aspectRatio(of: source) {
                await shared.reportSize(key: key, aspect: aspect, identity: identity)
            }
            await shared.reportFinal(key: key, identity: identity, outcome: .final(outcome))
            return
        }
        guard let payload = MediaPayload.decode(data: data, pixelWidth: pixelWidth) else {
            let isImageType = contentType?.hasPrefix("image/") == true
            await shared.reportFinal(
                key: key, identity: identity,
                outcome: .final(.failure(isImageType ? .decoding : .notAnImage(contentType: contentType))))
            return
        }
        await shared.reportSize(key: key, aspect: payload.aspectRatio, identity: identity)
        await shared.reportFinal(key: key, identity: identity, outcome: .final(.image(payload)))
    }

    /// Reads the incremental source's size, if the header bytes have arrived. One header
    /// parse per chunk until the size is known — cheap, and it stops the moment it answers.
    private static func incrementalSize(_ probe: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(probe, 0, nil) as? [CFString: Any],
            let width = (props[kCGImageSourcePixelWidth] as? NSNumber)?.doubleValue,
            let height = (props[kCGImageSourcePixelHeight] as? NSNumber)?.doubleValue,
            width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func driveDaemon(
        ref: DaemonFileRef, pixelWidth: Int, key: String, capBytes: Int64?
    ) async {
        let identity = liveKey(ref: ref)
        guard let fetch = await shared.daemonFetch else {
            // Unreachable through the cards (they gate on the host values first); fail closed.
            await shared.reportFinal(key: key, identity: identity, outcome: .final(.failure(.other)))
            return
        }
        // Memory first (the live key holds this session's freshest bytes per path), then
        // disk: the revisioned entry when the revision is known — authoritative for that
        // version — else the unrevisioned entry. A revisioned miss is a real miss: the bytes
        // changed, so stale disk must not serve.
        let fetchResult: DaemonFileBytes
        if let revision = ref.revision, let cached = diskRead(key: diskKey(ref: ref, revision: revision)) {
            fetchResult = DaemonFileBytes(data: cached, revision: revision)
        } else if ref.revision == nil, let cached = diskRead(key: diskKey(ref: ref, revision: nil)) {
            fetchResult = DaemonFileBytes(data: cached, revision: nil)
        } else {
            guard let fetched = await fetch(ref) else {
                await shared.reportFinal(
                    key: key, identity: identity, outcome: .final(.failure(.other)))
                return
            }
            fetchResult = fetched
            if Int64(fetchResult.data.count) > maxDaemonBytes {
                await shared.reportFinal(
                    key: key, identity: identity,
                    outcome: .final(.failure(.tooLarge(bytes: Int64(fetchResult.data.count)))))
                return
            }
            diskWrite(data: fetchResult.data, key: diskKey(ref: ref, revision: fetchResult.revision))
        }
        let data = fetchResult.data
        if let capBytes, Int64(data.count) > capBytes {
            await shared.reportFinal(
                key: key, identity: identity,
                outcome: .final(.failure(.tooLarge(bytes: Int64(data.count)))))
            return
        }
        if looksLikeSVG(data), let source = text(data) {
            let aspect = RichSVGIntrinsic.aspectRatio(of: source)
            let outcome = MediaOutcome.svg(source: source, aspectRatio: aspect)
            if let aspect { await shared.reportSize(key: key, aspect: aspect, identity: identity) }
            await shared.reportFinal(key: key, identity: identity, outcome: .final(outcome))
            return
        }
        guard let payload = MediaPayload.decode(data: data, pixelWidth: pixelWidth) else {
            await shared.reportFinal(
                key: key, identity: identity, outcome: .final(.failure(.decoding)))
            return
        }
        await shared.reportSize(key: key, aspect: payload.aspectRatio, identity: identity)
        await shared.reportFinal(key: key, identity: identity, outcome: .final(.image(payload)))
    }

    private static func mapURLError(_ error: URLError) -> MediaFailure {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
            .internationalRoamingOff, .callIsActive:
            return .offline
        case .timedOut, .cannotFindHost, .cannotConnectToHost:
            return .timedOut
        default:
            return .other
        }
    }

    // MARK: Keys

    /// The flight key: one stream per (content, decode bucket).
    private func streamKey(source: MediaSource, pixelWidth: Int) -> String {
        "\(identityKey(source: source))|\(pixelWidth)"
    }

    /// The content identity: the normalized URL, or the daemon live key. Sizes and failures
    /// are remembered here, so they survive pixel eviction and bucket changes.
    private func identityKey(source: MediaSource) -> String {
        switch source {
        case .remote(let url): url.absoluteString
        case .daemon(let ref): Self.liveKey(ref: ref)
        }
    }

    /// The memory identity of a daemon file: its location, not its version. The memory cache
    /// holds this session's freshest bytes per path (overwritten by every fetch); the disk
    /// below versions by revision, so an edited file refreshes instead of serving old bytes.
    static func liveKey(ref: DaemonFileRef) -> String {
        "daemon|\(ref.workspaceID)|\(ref.path)"
    }

    /// The disk identity: the content hash, versioned by revision when the daemon sent one.
    /// A new revision is a new file on disk; the LRU bounds the accumulation.
    static func diskKey(ref: DaemonFileRef, revision: String?) -> String {
        let effective = revision ?? ref.revision ?? ""
        var hasher = SHA256()
        for part in [ref.workspaceID, ref.path, effective] {
            hasher.update(data: Data("\(part)\0".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Daemon disk cache (off main, LRU 500 MB)

    private static func diskDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "daemon-media", directoryHint: .isDirectory)
    }

    /// Reads the disk entry and refreshes its age, so a scroll-back keeps what it uses.
    private static func diskRead(key: String) -> Data? {
        guard let url = diskDirectory()?.appending(path: key, directoryHint: .notDirectory),
            let data = try? Data(contentsOf: url)
        else { return nil }
        // best-effort: a touch failure must never fail the read.
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    /// Writes one entry, then evicts the oldest until the directory fits the budget.
    /// Both passes are O(files) and run off main, only when bytes actually arrived.
    private static func diskWrite(data: Data, key: String) {
        guard let directory = diskDirectory(),
            let url = Optional(directory.appending(path: key, directoryHint: .notDirectory))
        else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        evictDiskIfNeeded(directory: directory)
    }

    private static func evictDiskIfNeeded(directory: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys)
        else { return }
        var entries: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0
        for file in files {
            guard
                let values = try? file.resourceValues(forKeys: Set(keys)),
                let size = values.fileSize, let date = values.contentModificationDate
            else { continue }
            entries.append((file, Int64(size), date))
            total += Int64(size)
        }
        guard total > diskBudget else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
            if total <= diskBudget { break }
        }
    }

    // MARK: URLs

    /// `URL(string:)` refuses a handful of things that people (and agents) do write. Encode the
    /// leftovers rather than dropping the image on the floor.
    static func target(for urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed) { return url }
        return trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
            .flatMap(URL.init(string:))
    }

    private static func isSVGHint(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "svg" || url.absoluteString.lowercased().contains(".svg")
    }

    /// A markup document with an `<svg` near the top. Guards against a `.svg` URL that actually
    /// serves an HTML error page with a 200.
    private static func looksLikeSVG(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(4096), as: UTF8.self)
        guard head.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") else {
            return false
        }
        return head.range(of: "<svg", options: .caseInsensitive) != nil
    }

    private static func text(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: data: URLs

    private static func decodeDataURL(_ url: URL, pixelWidth: Int) async -> MediaEvent {
        guard let (data, contentType) = splitDataURL(url.absoluteString) else {
            return .final(.failure(.notAnImage(contentType: nil)))
        }
        if contentType?.contains("svg") == true || looksLikeSVG(data) {
            guard let source = text(data) else { return .final(.failure(.decoding)) }
            return .final(.svg(
                source: source, aspectRatio: RichSVGIntrinsic.aspectRatio(of: source)))
        }
        guard data.count <= maxBytes else {
            return .final(.failure(.tooLarge(bytes: Int64(data.count))))
        }
        guard let payload = await decode(data, pixelWidth: pixelWidth) else {
            return .final(.failure(.decoding))
        }
        return .final(.image(payload))
    }

    /// `data:[<mediatype>][;base64],<payload>` → bytes and media type. `URLSession` cannot load
    /// a `data:` URL at all, which is why these images never appeared.
    private static func splitDataURL(_ string: String) -> (Data, String?)? {
        guard string.lowercased().hasPrefix("data:"), let comma = string.firstIndex(of: ",")
        else { return nil }
        let meta = string[string.index(string.startIndex, offsetBy: 5)..<comma]
        let payload = String(string[string.index(after: comma)...])
        let mediaType = meta.split(separator: ";").first.map(String.init).flatMap {
            $0.isEmpty ? nil : $0
        }
        if meta.lowercased().hasSuffix(";base64") {
            guard let data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
            else { return nil }
            return (data, mediaType)
        }
        guard let decoded = payload.removingPercentEncoding, let data = decoded.data(using: .utf8)
        else { return nil }
        return (data, mediaType)
    }

    // MARK: Decode (off main, downsampled)

    /// One ImageIO pass at the card's width (`ImageDownsampler`), never a full-size bitmap. A
    /// 4000 px photo costs a 1200 px buffer, not 48 MB. An animated GIF yields its first frame.
    private static func decode(_ data: Data, pixelWidth: Int) async -> MediaPayload? {
        await Task.detached(priority: .userInitiated) {
            MediaPayload.decode(data: data, pixelWidth: pixelWidth)
        }.value
    }
}

extension MediaPayload {
    /// The downsample itself, off the pipeline's actor and off main. Width-exact: a tall portrait
    /// is decoded so its **width** matches the card, not its longest side (H5 round 2 review).
    static func decode(data: Data, pixelWidth: Int) -> MediaPayload? {
        guard
            let image = ImageDownsampler.image(
                data: data, pixelWidth: Double(pixelWidth), maxSide: 2048)
        else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        return MediaPayload(image: image, aspectRatio: size.width / size.height)
    }
}
#endif
