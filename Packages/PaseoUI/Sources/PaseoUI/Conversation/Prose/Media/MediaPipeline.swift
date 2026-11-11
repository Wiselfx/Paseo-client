#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import Synchronization
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
    /// More than one frame (GIF/APNG/WebP): the transcript shows `image` (the first frame)
    /// with a badge; only the viewer animates.
    let isAnimated: Bool
    /// The full bytes, carried only for small animated images (≤ 8 MB) so the viewer can
    /// decode frames without a second fetch. Nil for stills — they never need it.
    let fullData: Data?

    init(image: UIImage, aspectRatio: CGFloat, isAnimated: Bool = false, fullData: Data? = nil) {
        self.image = image
        self.aspectRatio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
        self.isAnimated = isAnimated
        self.fullData = fullData
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
    /// Raw bytes with a caller-provided flight identity (the Files panel's decoded file:
    /// the bytes are already here, so the pipeline only decodes — never fetches).
    case data(Data, String)
}

/// Raw daemon bytes plus the revision the daemon reported, if any. The controller builds
/// this from `checkout.files.fetch(path, maxBytes:)`; the pipeline owns everything after.
struct DaemonFileBytes: Sendable {
    var data: Data
    var revision: String?
}

/// What a daemon read resolves to. `tooLarge` is the daemon refusing `maxBytes` (it stats
/// the file first and never transfers it); `unavailable` is everything else.
///
/// The refusal arrives as `PaseoStoreError.missingFile` carrying the daemon's own text
/// ("File is too large to display" on the frozen reference); matching it is upstream-
/// string-dependent and documented at the single mapping site, in the controller.
enum DaemonMediaResult: Sendable {
    case bytes(DaemonFileBytes)
    case tooLarge
    case unavailable
}

/// One workspace's daemon read: bytes (with revision) for a ref, bounded by `maxBytes`.
/// Set by the owning controller; last registration per workspace wins.
typealias DaemonMediaFetch = @Sendable (DaemonFileRef, Int) async -> DaemonMediaResult

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
/// - the daemon-file source (`FileExplorerRequest(mode: .file, acceptBinary: true)` behind
///   per-workspace resolvers, the request capped before transfer), cached on disk in
///   `Caches/daemon-media/<sha256>`, LRU at 500 MB;
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

    /// One step of the streaming download: the response first (always), then body chunks.
    /// `URLSession` guarantees the order per task, so the driver validates the status
    /// before a single body byte is kept.
    enum StreamStep: Sendable {
        case response(HTTPURLResponse)
        case chunk(Data)
    }

    /// Routes one data task's response and chunks into a stream. `Mutex`-guarded (the
    /// codebase's lock): delegate callbacks arrive on the session queue, never the actor.
    ///
    /// Why a delegate at all: `URLSession.AsyncBytes` iterates `UInt8`, so a per-byte loop
    /// would run the probe, the ceiling and an actor hop per byte — O(n²) over the header
    /// and millions of hops per image. The delegate yields real network chunks, and the
    /// driver's per-chunk work is O(1): append, one ceiling compare, one probe until the
    /// size is known, and an actor hop only when the 10 % bucket flips.
    private final class MediaStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable
    {
        static let shared = MediaStreamDelegate()
        private let streams = Mutex<[Int: AsyncThrowingStream<StreamStep, Error>.Continuation]>(
            [:])

        func openStream(for task: URLSessionDataTask) -> AsyncThrowingStream<StreamStep, Error> {
            AsyncThrowingStream { continuation in
                self.streams.withLock { $0[task.taskIdentifier] = continuation }
                // An early exit (the ceiling) releases the stream; termination stops the
                // socket. A finished task cancels a finished task: a no-op.
                continuation.onTermination = { _ in task.cancel() }
                task.resume()
            }
        }

        func urlSession(
            _ session: URLSession, dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            guard let http = response as? HTTPURLResponse else {
                completionHandler(.cancel)
                return
            }
            streams.withLock { $0[dataTask.taskIdentifier] }?.yield(.response(http))
            completionHandler(.allow)
        }

        func urlSession(
            _ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data
        ) {
            streams.withLock { $0[dataTask.taskIdentifier] }?.yield(.chunk(data))
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
        ) {
            let continuation = streams.withLock { $0.removeValue(forKey: task.taskIdentifier) }
            if let error {
                if (error as? URLError)?.code == .cancelled {
                    continuation?.finish()
                } else {
                    continuation?.finish(throwing: error)
                }
            } else {
                continuation?.finish()
            }
        }
    }

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
        // A delegate data task populates `URLCache` like any other, for a default config
        // with a cacheable response — relied on for scroll-back and relaunches.
        return URLSession(
            configuration: configuration, delegate: MediaStreamDelegate.shared,
            delegateQueue: nil)
    }()

    /// One flight per (source, pixel bucket): every card showing the same bytes shares it.
    private struct Flight {
        /// Continuations currently watching, by subscription.
        var watchers: [UUID: AsyncStream<MediaEvent>.Continuation] = [:]
        /// The last progress bucket emitted (10 % steps), so the ring moves O(10) times.
        var lastBucket = -1
    }

    private var flights: [String: Flight] = [:]
    /// Daemon reads, one per workspace. Every controller registers its workspace on
    /// configure and unregisters on dealloc; last registration per workspace wins. A
    /// missing resolver is "not reachable yet", never a memoized failure.
    private var resolvers: [String: (token: UUID, fetch: DaemonMediaFetch)] = [:]
    /// Live keys fetched this launch. The disk entry for a path is served only when
    /// validated here or requested as the offline fallback: a first view in a new session
    /// always refetches, so an agent-edited file never serves last launch's bytes.
    private var validatedThisSession: Set<String> = []

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

    /// Registers the workspace's daemon read and returns its token. Called by each
    /// conversation controller with a stable closure; last registration per workspace
    /// wins, and unregistration only removes the entry holding its own token — so a
    /// deallocated controller never unregisters its successor in the same workspace.
    func registerDaemonFetch(for workspaceID: String, _ fetch: @escaping DaemonMediaFetch) -> UUID {
        let token = UUID()
        resolvers[workspaceID] = (token, fetch)
        return token
    }

    func unregisterDaemonFetch(for workspaceID: String, token: UUID) {
        guard resolvers[workspaceID]?.token == token else { return }
        resolvers.removeValue(forKey: workspaceID)
    }

    private func resolver(for workspaceID: String) -> DaemonMediaFetch? {
        resolvers[workspaceID]?.fetch
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
        ignoreFailureCache: Bool = false, maxSide: Double = 2048, cacheResult: Bool = true,
        allowStaleDisk: Bool = false
    ) async -> AsyncStream<MediaEvent> {
        // The cap belongs to whoever started the flight: a tap (cap nil) keys differently
        // from a gated load, so an explicit fetch always downloads fully.
        let key = streamKey(source: source, pixelWidth: pixelWidth, capBytes: capBytes)
        let identity = Self.identityKey(source: source)

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
            return await Self.single(Self.decodeDataURL(url, pixelWidth: pixelWidth))
        }
        if case .remote(let url) = source, url.scheme?.lowercased() == "blob" {
            // A blob handle only means something inside the browser that made it.
            return Self.single(.final(.failure(.unsupportedScheme("blob"))))
        }
        if case .daemon(let ref) = source, resolvers[ref.workspaceID] == nil {
            // No resolver: unreachable, not broken — fail closed with no flight, no memo,
            // no report. The card retries when a controller registers.
            return Self.single(.final(.failure(.other)))
        }

        let (stream, continuation) = AsyncStream<MediaEvent>.makeStream()
        let id = UUID()
        continuation.onTermination = { _ in
            Task { await MediaPipeline.shared.detach(id: id, key: key) }
        }
        // Sharing subsumes the old in-flight cap: one flight per (content, bucket, cap)
        // however many cards watch it, and the entry is dropped when the driver reports.
        // Distinct content still downloads concurrently (per-host connection limits apply).
        var flight = flights[key] ?? Flight()
        let isNew = flights[key] == nil
        flight.watchers[id] = continuation
        flights[key] = flight
        if isNew {
            Task.detached {
                [source, pixelWidth, key, capBytes, maxSide, cacheResult, allowStaleDisk] in
                await MediaPipeline.drive(
                    source: source, pixelWidth: pixelWidth, key: key, capBytes: capBytes,
                    maxSide: maxSide, cacheResult: cacheResult, allowStaleDisk: allowStaleDisk)
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
        source: MediaSource, pixelWidth: Int, ignoreFailureCache: Bool = false,
        maxSide: Double = 2048, cacheResult: Bool = true
    ) async -> MediaOutcome {
        for await event in await events(
            source: source, pixelWidth: pixelWidth, ignoreFailureCache: ignoreFailureCache,
            maxSide: maxSide, cacheResult: cacheResult
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

    /// Fans a driverless outcome out to a flight's watchers with no cache writes: the
    /// no-resolver path (missing, not broken) must never memoize.
    private func reportUnresolved(key: String) {
        let flight = flights.removeValue(forKey: key)
        guard let flight else { return }
        for continuation in flight.watchers.values {
            continuation.yield(.final(.failure(.other)))
            continuation.finish()
        }
    }

    private func reportFinal(key: String, identity: String, outcome: MediaOutcome, cache: Bool = true) {
        let flight = flights.removeValue(forKey: key)
        switch outcome {
        case .image(let payload):
            // Both entries carry the real cost: an evicted bucket entry must not leave
            // the bitmap surviving uncounted, or `totalCostLimit` stops bounding memory.
            if cache {
                let cost = Self.cost(of: payload)
                Self.decoded.setObject(payload, forKey: key as NSString, cost: cost)
                Self.decoded.setObject(payload, forKey: identity as NSString, cost: cost)
            }
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
        return Int(max(width, 1) * max(height, 1) * 4) + (payload.fullData?.count ?? 0)
    }

    // MARK: Drivers (detached: never actor-isolated, never main)

    /// One download: stream the bytes, probe the size early, enforce the ceiling, decode at
    /// display size off main. Reports back through the actor; the actor fans out to watchers.
    private static func drive(
        source: MediaSource, pixelWidth: Int, key: String, capBytes: Int64?,
        maxSide: Double, cacheResult: Bool, allowStaleDisk: Bool
    ) async {
        switch source {
        case .remote(let url):
            await driveRemote(
                url: url, pixelWidth: pixelWidth, key: key, capBytes: capBytes,
                maxSide: maxSide, cacheResult: cacheResult)
        case .daemon(let ref):
            await driveDaemon(
                ref: ref, pixelWidth: pixelWidth, key: key, capBytes: capBytes,
                maxSide: maxSide, cacheResult: cacheResult, allowStaleDisk: allowStaleDisk)
        case .data(let bytes, _):
            await finishImageData(
                data: bytes, pixelWidth: pixelWidth, key: key,
                identity: identityKey(source: source),
                maxSide: maxSide, cacheResult: cacheResult)
        }
    }

    private static func driveRemote(
        url: URL, pixelWidth: Int, key: String, capBytes: Int64?,
        maxSide: Double, cacheResult: Bool
    ) async {
        let identity = url.absoluteString
        var request = URLRequest(
            url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        // Not a child task of the caller: scrolling away does not cancel the bytes we
        // are about to want on the way back.
        let task = session.dataTask(with: request)
        let stream = MediaStreamDelegate.shared.openStream(for: task)
        var data = Data()
        // `nil` when WebKit cannot start the source; the size events just never fire and the
        // final decode decides, exactly like a response with no size hints.
        let probe: CGImageSource? = CGImageSourceCreateIncremental(nil)
        let svgHinted = isSVGHint(url)
        var sizeSent = false
        var ceiling = Int64(maxBytes)
        var contentType: String?
        var expected: Int64 = -1
        var lastBucket = -1
        do {
            for try await step in stream {
                switch step {
                case .response(let http):
                    guard (200..<300).contains(http.statusCode) else {
                        task.cancel()
                        await shared.reportFinal(
                            key: key, identity: identity,
                            outcome: .failure(.http(http.statusCode)))
                        return
                    }
                    contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased()
                    // The ceiling for this stream: the policy cap, inside the hard wire
                    // cap. An SVG-ish response only ever needs its 2 MB.
                    ceiling = min(capBytes ?? Int64(maxBytes), Int64(maxBytes))
                    if contentType?.contains("svg") == true || svgHinted {
                        ceiling = min(ceiling, Int64(maxSVGBytes))
                    }
                    expected = http.expectedContentLength
                    if expected > 0 {
                        data.reserveCapacity(Int(min(expected, ceiling)))
                    }
                case .chunk(let piece):
                    data.append(contentsOf: piece)
                    if Int64(data.count) > ceiling {
                        // Explicit: stop the socket now, don't wait for termination.
                        task.cancel()
                        await shared.reportFinal(
                            key: key, identity: identity,
                            outcome: .failure(.tooLarge(bytes: Int64(data.count))))
                        return
                    }
                    if !sizeSent, let probe {
                        CGImageSourceUpdateData(probe, data as CFData, false)
                        if let size = incrementalSize(probe), size.height > 0 {
                            sizeSent = true
                            await shared.reportSize(
                                key: key, aspect: size.width / size.height,
                                identity: identity)
                        } else if svgHinted, looksLikeSVG(data) {
                            // Markup, not pixels: no incremental size to learn; the viewBox
                            // parse at the end reserves the box.
                            sizeSent = true
                        }
                    }
                    if expected > 0 {
                        // The bucket lives in the driver: the actor only hears a flip.
                        let bucket = Int(
                            (Double(data.count) / Double(expected) * 10).rounded(.down))
                        if bucket != lastBucket {
                            lastBucket = bucket
                            await shared.reportProgress(
                                key: key,
                                fraction: min(max(Double(data.count) / Double(expected), 0), 1))
                        }
                    }
                }
            }
        } catch {
            await shared.reportFinal(
                key: key, identity: identity, outcome: .failure(mapStreamError(error)))
            return
        }
        if data.count > maxBytes {
            await shared.reportFinal(
                key: key, identity: identity,
                outcome: .failure(.tooLarge(bytes: Int64(data.count))))
            return
        }
        if contentType?.contains("svg") == true || (isSVGHint(url) && looksLikeSVG(data)) {
            guard data.count <= maxSVGBytes else {
                await shared.reportFinal(
                    key: key, identity: identity,
                    outcome: .failure(.tooLarge(bytes: Int64(data.count))))
                return
            }
            guard let source = text(data), looksLikeSVG(data) else {
                await shared.reportFinal(
                    key: key, identity: identity, outcome: .failure(.decoding))
                return
            }
            let outcome = MediaOutcome.svg(
                source: source, aspectRatio: RichSVGIntrinsic.aspectRatio(of: source))
            if let aspect = RichSVGIntrinsic.aspectRatio(of: source) {
                await shared.reportSize(key: key, aspect: aspect, identity: identity)
            }
            await shared.reportFinal(key: key, identity: identity, outcome: outcome)
            return
        }
        guard
            let payload = MediaPayload.decode(data: data, pixelWidth: pixelWidth, maxSide: maxSide)
        else {
            let isImageType = contentType?.hasPrefix("image/") == true
            await shared.reportFinal(
                key: key, identity: identity,
                outcome: .failure(isImageType ? .decoding : .notAnImage(contentType: contentType)))
            return
        }
        await shared.reportSize(key: key, aspect: payload.aspectRatio, identity: identity)
        await shared.reportFinal(
            key: key, identity: identity, outcome: .image(payload),
            cache: cacheResult)
    }

    /// Reads the incremental source's size, if the header bytes have arrived. One header
    /// parse per chunk until the size is known — cheap, and it stops the moment it answers.
    private static func incrementalSize(_ probe: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(probe, 0, nil) as? [CFString: Any],
            let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
            width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func driveDaemon(
        ref: DaemonFileRef, pixelWidth: Int, key: String, capBytes: Int64?,
        maxSide: Double, cacheResult: Bool, allowStaleDisk: Bool
    ) async {
        let identity = liveKey(ref: ref)
        guard let fetch = await shared.resolver(for: ref.workspaceID) else {
            // Unregistered mid-flight: unreachable, not broken — fan out with no memo.
            await shared.reportUnresolved(key: key)
            return
        }
        // Memory first (the live key holds this session's freshest bytes per path), then
        // disk — but only when validated this session, or as the offline fallback. A first
        // view in a new session always refetches: the daemon has no cheap per-file stat,
        // and a parent listing per image would cost more than the fetch it saves.
        // The read key is the request identity — the same function the write uses.
        if await shared.validatedContains(identity) || allowStaleDisk,
            let cached = diskRead(key: diskKey(ref: ref, revision: ref.revision))
        {
            await finishImageData(
                data: cached, pixelWidth: pixelWidth, key: key, identity: identity,
                maxSide: maxSide, cacheResult: cacheResult)
            return
        }
        // The cap is the request's ceiling, so an oversize file is never transferred.
        let requestCap = Int(min(capBytes ?? maxDaemonBytes, maxDaemonBytes))
        let fetchResult: DaemonFileBytes
        if let revision = ref.revision,
            let cached = diskRead(key: diskKey(ref: ref, revision: revision))
        {
            fetchResult = DaemonFileBytes(data: cached, revision: revision)
        } else {
            switch await fetch(ref, requestCap) {
            case .bytes(let fetched):
                fetchResult = fetched
                await shared.noteValidated(identity)
                // The write key is the request identity — the same function the read
                // uses, so they always agree. The response revision rides in a sidecar
                // for a later stat-based validation; it is never part of a key the
                // reader cannot reconstruct.
                diskWrite(data: fetched.data, key: diskKey(ref: ref, revision: ref.revision))
                if let revision = fetched.revision {
                    diskWriteText(
                        revision,
                        key: diskKey(ref: ref, revision: ref.revision) + ".rev")
                }
            case .tooLarge:
                await shared.reportFinal(
                    key: key, identity: identity, outcome: .failure(.tooLarge(bytes: nil)))
                return
            case .unavailable:
                // Not reachable yet (reconnecting, descriptor missing): fan out with no
                // memo, so the card retries on its next appear.
                await shared.reportUnresolved(key: key)
                return
            }
        }
        await finishImageData(
            data: fetchResult.data, pixelWidth: pixelWidth, key: key, identity: identity,
            maxSide: maxSide, cacheResult: cacheResult)
    }

    private func validatedContains(_ liveKey: String) -> Bool {
        validatedThisSession.contains(liveKey)
    }

    private func noteValidated(_ liveKey: String) {
        validatedThisSession.insert(liveKey)
    }

    /// The shared tail for arrived bytes: SVG routing plus the width-exact off-main
    /// decode. Bytes that already arrived are never capped — the ceiling applies to the
    /// transfer (the request), not to bytes in hand.
    private static func finishImageData(
        data: Data, pixelWidth: Int, key: String, identity: String,
        maxSide: Double, cacheResult: Bool
    ) async {
        if looksLikeSVG(data), let source = text(data) {
            let aspect = RichSVGIntrinsic.aspectRatio(of: source)
            let outcome = MediaOutcome.svg(source: source, aspectRatio: aspect)
            if let aspect { await shared.reportSize(key: key, aspect: aspect, identity: identity) }
            await shared.reportFinal(key: key, identity: identity, outcome: outcome)
            return
        }
        guard
            let payload = MediaPayload.decode(data: data, pixelWidth: pixelWidth, maxSide: maxSide)
        else {
            await shared.reportFinal(
                key: key, identity: identity, outcome: .failure(.decoding))
            return
        }
        await shared.reportSize(key: key, aspect: payload.aspectRatio, identity: identity)
        await shared.reportFinal(
            key: key, identity: identity, outcome: .image(payload),
            cache: cacheResult)
    }

    private static func mapStreamError(_ error: Error) -> MediaFailure {
        if let urlError = error as? URLError { return mapURLError(urlError) }
        return .other
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

    /// The flight key: one stream per (content, decode bucket, cap). The cap is part of
    /// the key so a tap never inherits a gated flight's ceiling.
    private func streamKey(source: MediaSource, pixelWidth: Int, capBytes: Int64?) -> String {
        "\(Self.identityKey(source: source))|\(pixelWidth)|\(capBytes.map(String.init) ?? "full")"
    }

    /// The content identity: the normalized URL, the daemon live key, or the caller's data
    /// identity. Sizes and failures are remembered here, so they survive pixel eviction
    /// and bucket changes.
    private static func identityKey(source: MediaSource) -> String {
        switch source {
        case .remote(let url): url.absoluteString
        case .daemon(let ref): Self.liveKey(ref: ref)
        case .data(_, let id): "data|\(id)"
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
    /// Writes one text sidecar (the daemon's revision, for a later stat-based
    /// validation). Best-effort like every disk write here.
    private static func diskWriteText(_ text: String, key: String) {
        guard let directory = diskDirectory(),
            let url = Optional(directory.appending(path: key, directoryHint: .notDirectory)),
            let data = text.data(using: .utf8)
        else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

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
        guard let payload = await decode(data, pixelWidth: pixelWidth, maxSide: 2048) else {
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
    private static func decode(_ data: Data, pixelWidth: Int, maxSide: Double) async -> MediaPayload? {
        await Task.detached(priority: .userInitiated) {
            MediaPayload.decode(data: data, pixelWidth: pixelWidth, maxSide: maxSide)
        }.value
    }
}

extension MediaPayload {
    /// Animated bytes are worth carrying only when they fit a viewer page comfortably.
    static let maxCarriedAnimationBytes = 8 * 1024 * 1024

    /// The downsample itself, off the pipeline's actor and off main. Width-exact: a tall portrait
    /// is decoded so its **width** matches the card, not its longest side (H5 round 2 review).
    static func decode(data: Data, pixelWidth: Int, maxSide: Double = 2048) -> MediaPayload? {
        guard
            let image = ImageDownsampler.image(
                data: data, pixelWidth: Double(pixelWidth), maxSide: maxSide)
        else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let animated = (frameCount(of: data) ?? 1) > 1
        let fullData = animated && data.count <= maxCarriedAnimationBytes ? data : nil
        return MediaPayload(
            image: image, aspectRatio: size.width / size.height,
            isAnimated: animated, fullData: fullData)
    }

    /// The frame count from the header alone — no bitmap, no decode.
    private static func frameCount(of data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceGetCount(source)
    }
}
#endif
