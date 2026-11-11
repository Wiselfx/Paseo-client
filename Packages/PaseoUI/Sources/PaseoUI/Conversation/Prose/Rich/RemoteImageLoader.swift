#if canImport(UIKit)
import Foundation
import ImageIO
import SwiftUI
import UIKit

// MARK: - Results

/// A decoded remote image and the shape it wants to be laid out in.
///
/// A class, not a struct, for two reasons: `NSCache` stores objects, and the payload crosses
/// from the decode task to the main actor. `UIImage` is immutable and safe to hand around;
/// `@unchecked Sendable` states that in one place instead of at every call site.
final class RemoteImagePayload: @unchecked Sendable {
    let image: UIImage
    /// Width / height as decoded, so a card can reserve its box before the pixels land and
    /// never shift what is above or below it.
    let aspectRatio: CGFloat

    init(image: UIImage, aspectRatio: CGFloat) {
        self.image = image
        self.aspectRatio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
    }
}

/// Why an image did not load, phrased for the card (H5 §3: honest and useful).
enum RemoteImageFailure: Error, Equatable, Sendable {
    case badURL
    case unsupportedScheme(String)
    case notAnImage(contentType: String?)
    case http(Int)
    case offline
    case timedOut
    case tooLarge
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

enum RemoteImageOutcome: Sendable {
    case image(RemoteImagePayload)
    /// An SVG: the caller renders it through the shared offscreen snapshot renderer, which
    /// needs a width, the colour scheme and the main actor.
    case svg(source: String, aspectRatio: CGFloat?)
    case failure(RemoteImageFailure)
}

// MARK: - Sizing

enum RemoteImageSizing {
    /// The pixel width to decode at: the card's width in points × the screen scale, rounded up
    /// to a 128 px bucket so a one-point layout change does not throw the decode away.
    static func pixelWidth(points: CGFloat, scale: CGFloat) -> Int {
        guard points > 1, scale > 0 else { return 640 }
        let pixels = points * scale
        let bucket = (pixels / 128).rounded(.up) * 128
        return Int(min(max(bucket, 128), 2048))
    }
}

// MARK: - Loader

/// The one remote image path for the whole app (H5 §2).
///
/// Before this, every image was an `AsyncImage`: its own default-session request with no app
/// identity, no decoded cache, and a task tied to the view's lifetime — so scrolling back
/// re-downloaded, re-decoded and re-flashed a placeholder, and scrolling past mid-load could
/// leave a card in `.failure` for good.
///
/// This actor owns the session (sized `URLCache`, `Paseo/<version>` User-Agent, redirects,
/// timeouts), de-duplicates in-flight work per URL + pixel bucket, and keeps three bounded
/// caches: decoded images, the shape of every URL it has seen, and a short-lived failure memo
/// so a card scrolled past does not hammer a dead host.
///
/// A load started for a card that scrolls away is *not* cancelled: it finishes, fills the cache
/// and is instant when the card comes back. Only the card's own state write is skipped.
actor RemoteImageLoader {
    static let shared = RemoteImageLoader()

    /// ~64 decoded images or 48 MB, whichever comes first. Past that the oldest are a scroll
    /// away from being refetched from `URLCache`, which is cheaper than starving the app.
    private static let imageCacheCountLimit = 64
    private static let imageCacheCostLimit = 48 * 1024 * 1024
    /// An image is at most this big on the wire; anything larger is a file, not a chat image.
    static let maxBytes = 20 * 1024 * 1024
    /// SVGs are markup and are rendered as a document; a screenshot-sized drawing fits easily.
    static let maxSVGBytes = 2 * 1024 * 1024
    /// How long a failure is remembered, so scrolling over a dead link does not refetch it.
    private static let failureTTL: TimeInterval = 60
    /// In-flight work beyond this is not de-duplicated, so a wall of images cannot pile up.
    private static let maxInFlight = 8

    /// `NSCache` is documented thread-safe; `nonisolated(unsafe)` says so to the compiler and
    /// lets the card's first frame read it without an actor hop.
    nonisolated(unsafe) private static let decoded = NSCache<NSString, RemoteImagePayload>()
    nonisolated(unsafe) private static let shapes = NSCache<NSString, NSNumber>()

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

    private var inFlight: [String: Task<RemoteImageOutcome, Never>] = [:]
    private var recentFailures: [String: (failure: RemoteImageFailure, at: Date)] = [:]

    init() {
        Self.decoded.countLimit = Self.imageCacheCountLimit
        Self.decoded.totalCostLimit = Self.imageCacheCostLimit
        Self.shapes.countLimit = 512
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

    /// What we already know about a URL, for the card's very first body pass. An `NSCache`
    /// read is O(1) and thread-safe, so scrolling back draws the image on the first frame
    /// instead of a placeholder that flashes out one runloop later.
    static func cached(for urlString: String) -> RemoteImagePayload? {
        decoded.object(forKey: urlString as NSString)
    }

    /// The aspect ratio known for a URL, even after its pixels were evicted.
    static func cachedAspect(for urlString: String) -> CGFloat? {
        shapes.object(forKey: urlString as NSString)?.doubleValue
    }

    /// Remember a shape learned some other way (an SVG's `viewBox`, a snapshot).
    static func rememberAspect(_ aspectRatio: CGFloat, for urlString: String) {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return }
        shapes.setObject(NSNumber(value: Double(aspectRatio)), forKey: urlString as NSString)
    }

    // MARK: Load

    /// Loads `urlString` at the given pixel width. Returns a cached image without touching the
    /// network when there is one; otherwise joins (or starts) the one fetch for that URL + size.
    func load(
        urlString: String, pixelWidth: Int, ignoreFailureCache: Bool = false
    ) async -> RemoteImageOutcome {
        guard let target = Self.target(for: urlString) else { return .failure(.badURL) }
        let identity = target.absoluteString
        let key = "\(identity)|\(pixelWidth)"

        if let cached = Self.decoded.object(forKey: key as NSString) {
            return .image(cached)
        }
        if let cached = Self.decoded.object(forKey: identity as NSString) {
            // The same picture at another bucket (a rotation, a sheet): right for the first
            // paint, and the exact size follows if it is asked for again.
            Self.decoded.setObject(cached, forKey: key as NSString, cost: 0)
            return .image(cached)
        }
        if !ignoreFailureCache, let memo = recentFailures[key],
            Date().timeIntervalSince(memo.at) < Self.failureTTL
        {
            return .failure(memo.failure)
        }

        let task: Task<RemoteImageOutcome, Never>
        if let running = inFlight[key] {
            task = running
        } else {
            task = Task { await Self.fetch(target: target, pixelWidth: pixelWidth) }
            if inFlight.count < Self.maxInFlight { inFlight[key] = task }
        }
        let outcome = await task.value
        inFlight[key] = nil

        switch outcome {
        case .image(let payload):
            Self.decoded.setObject(payload, forKey: key as NSString, cost: Self.cost(of: payload))
            Self.decoded.setObject(payload, forKey: identity as NSString, cost: 0)
            Self.shapes.setObject(
                NSNumber(value: Double(payload.aspectRatio)), forKey: identity as NSString)
            recentFailures[key] = nil
        case .failure(let failure):
            if recentFailures.count >= 32 { recentFailures.removeAll(keepingCapacity: true) }
            recentFailures[key] = (failure, Date())
        case .svg:
            recentFailures[key] = nil
        }
        return outcome
    }

    private static func cost(of payload: RemoteImagePayload) -> Int {
        let width = payload.image.size.width * payload.image.scale
        let height = payload.image.size.height * payload.image.scale
        return Int(max(width, 1) * max(height, 1) * 4)
    }

    // MARK: Fetch

    private static func fetch(target: URL, pixelWidth: Int) async -> RemoteImageOutcome {
        switch target.scheme?.lowercased() {
        case "data":
            return await decodePayloadURL(target, pixelWidth: pixelWidth)
        case "blob":
            // A blob handle only means something inside the browser that made it.
            return .failure(.unsupportedScheme("blob"))
        default:
            break
        }

        var request = URLRequest(
            url: target, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        do {
            // Not a child task of the caller: scrolling away does not cancel the bytes we
            // are about to want on the way back.
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            if let http, !(200..<300).contains(http.statusCode) {
                return .failure(.http(http.statusCode))
            }
            if data.count > maxBytes { return .failure(.tooLarge) }
            let contentType = http?.value(forHTTPHeaderField: "Content-Type")?.lowercased()

            if contentType?.contains("svg") == true || (isSVGHint(target) && looksLikeSVG(data)) {
                guard data.count <= maxSVGBytes else { return .failure(.tooLarge) }
                guard let source = text(data), looksLikeSVG(data) else { return .failure(.decoding) }
                return .svg(source: source, aspectRatio: RichSVGIntrinsic.aspectRatio(of: source))
            }
            guard let payload = await decode(data, pixelWidth: pixelWidth) else {
                let isImageType = contentType?.hasPrefix("image/") == true
                return .failure(isImageType ? .decoding : .notAnImage(contentType: contentType))
            }
            return .image(payload)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                .internationalRoamingOff, .callIsActive:
                return .failure(.offline)
            case .timedOut, .cannotFindHost, .cannotConnectToHost:
                return .failure(.timedOut)
            default:
                return .failure(.other)
            }
        } catch {
            return .failure(.other)
        }
    }

    // MARK: Decode (off main, downsampled)

    /// One ImageIO pass: read the header, make one thumbnail at `pixelWidth`, never materialise
    /// the full bitmap. A 4000 px photo costs a 1200 px buffer, not 48 MB on the main actor.
    /// An animated GIF yields its first frame and stops there.
    private static func decode(_ data: Data, pixelWidth: Int) async -> RemoteImagePayload? {
        await Task.detached(priority: .userInitiated) {
            RemoteImagePayload.decode(data: data, pixelWidth: pixelWidth)
        }.value
    }

    private static func text(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
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

    // MARK: data: URLs

    private static func decodePayloadURL(
        _ url: URL, pixelWidth: Int
    ) async -> RemoteImageOutcome {
        guard let (data, contentType) = splitDataURL(url.absoluteString) else {
            return .failure(.notAnImage(contentType: nil))
        }
        if contentType?.contains("svg") == true || looksLikeSVG(data) {
            guard let source = text(data) else { return .failure(.decoding) }
            return .svg(source: source, aspectRatio: RichSVGIntrinsic.aspectRatio(of: source))
        }
        guard data.count <= maxBytes else { return .failure(.tooLarge) }
        guard let payload = await decode(data, pixelWidth: pixelWidth) else {
            return .failure(.decoding)
        }
        return .image(payload)
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
}

extension RemoteImagePayload {
    /// The downsample itself, off the loader's actor: read the header, one thumbnail, one
    /// `UIImage`. Runs on the cooperative pool, never on the main actor. (The composer has its
    /// own twin of this in `ComposerImageProcessor.thumbnail`; they differ in what they return.)
    static func decode(data: Data, pixelWidth: Int) -> RemoteImagePayload? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
            CGImageSourceGetCount(source) > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, pixelWidth),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let image = UIImage(cgImage: cgImage)
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        return RemoteImagePayload(image: image, aspectRatio: size.width / size.height)
    }
}
#endif
