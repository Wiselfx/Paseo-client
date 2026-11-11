import Foundation

// MARK: - MediaFetchPolicy (G2 §12)

// NOTE: RemoteImagePipeline/G2: video/audio download through this policy in G11; the poster
// nuance (a bounded fetch for the poster frame vs the tap-gated full download) is decided
// there. This file only answers "fetch now, wait for a tap, or stay cached".

/// Network etiquette (§12): whether a piece of media downloads itself.
///
/// The rule: media downloads automatically only when the connection is cheap. Otherwise the
/// card shows what it would load and waits for a tap. Thumbnails are always cheap; the full
/// bytes of anything bigger wait on cellular data, Low Data Mode, the relay, or offline.
public enum MediaFetchPolicy: Equatable, Sendable {
    /// Fetch now, in the background, before the reader scrolls to it.
    case automatic
    /// Show the reserved box with what is known (size when known) and wait for a tap.
    case tapToDownload
    /// Offline: never fetch. Show what is cached, or the honest failure.
    case cacheOnly
}

/// What a card is about to load. Sizes are bytes on the wire; nil means unknown.
public enum MediaKind: Equatable, Sendable {
    /// Favicons, OG leftovers, anything ≤ 200 KB by construction. Always cheap.
    case thumbnail
    /// A transcript image: remote URL or daemon file.
    case image
    /// A video file (G11): the full download always waits; the poster is decided in G11.
    case video
    /// An audio file (G11): same as video.
    case audio
    /// YouTube embeds and link metadata: third-party calls that never use the relay.
    case youTube
    case linkPreview
}

/// The connection, as one value. Produced from `NetworkPathMonitor` plus the host session's
/// relay flag; cards read only the derived `MediaFetchPolicy` (R-1).
public struct MediaLinkCondition: Equatable, Sendable {
    public enum Interface: Equatable, Sendable {
        case wifi
        case cellular
        case wired
        case other
    }

    /// The cheapest interface currently up. `.other` (VPN, tethering glue) counts as cheap.
    public var interface: Interface
    /// Low Data Mode (`isConstrained`): the user pays per byte or asked to save.
    public var constrained: Bool
    /// The daemon is reached through the relay: slow, metered, and billed to its operator.
    public var isRelay: Bool
    /// No path at all: nothing may fetch.
    public var offline: Bool

    public init(
        interface: Interface = .wifi, constrained: Bool = false, isRelay: Bool = false,
        offline: Bool = false
    ) {
        self.interface = interface
        self.constrained = constrained
        self.isRelay = isRelay
        self.offline = offline
    }

    /// The status-quo assumption before the first path update lands: cheap and direct.
    public static let assumed = MediaLinkCondition()
}

/// Decides §12 for one card: pure, O(1), safe to call from `body` (R-1).
///
/// - `kind`: what the bytes are for.
/// - `knownBytes`: the size when something already knows it (a daemon listing, a cached
///   response). Nil means unknown: cheap links proceed optimistically and the streaming
///   download enforces `mediaDownloadCap` instead; the relay and Low Data Mode wait.
public func mediaFetchPolicy(
    kind: MediaKind, knownBytes: Int64?, condition: MediaLinkCondition
) -> MediaFetchPolicy {
    if condition.offline { return .cacheOnly }
    if kind == .thumbnail { return .automatic }
    if condition.constrained {
        // Low Data Mode: thumbnails are free; everything else waits for an explicit tap,
        // including the metadata calls (the card renders its text-only row).
        return .tapToDownload
    }
    switch kind {
    case .thumbnail:
        return .automatic
    case .image:
        if condition.isRelay {
            // Relay traffic is metered twice over: ≤ 1 MB rides along, the rest waits.
            // Unknown counts as over: it cannot prove it fits.
            if let knownBytes, knownBytes <= 1 * 1024 * 1024 { return .automatic }
            return .tapToDownload
        }
        // Wi-Fi, cellular, wired: ≤ 5 MB auto; unknown proceeds (the cap enforces it
        // mid-stream and flips the card to tap-to-download with the learned size).
        if let knownBytes, knownBytes > 5 * 1024 * 1024 { return .tapToDownload }
        return .automatic
    case .video, .audio:
        // Full media always waits (G11 owns the poster nuance); the box shows the size.
        return .tapToDownload
    case .youTube, .linkPreview:
        // Third-party metadata that never touches the relay or the daemon.
        return .automatic
    }
}

/// The in-flight ceiling for an `automatic` download, in bytes: past this the stream aborts
/// and the card flips to tap-to-download with the learned size. Nil means uncapped (the kind
/// never auto-downloads, or is cheap by construction).
public func mediaDownloadCap(kind: MediaKind, condition: MediaLinkCondition) -> Int64? {
    switch kind {
    case .thumbnail, .youTube, .linkPreview:
        return nil
    case .image:
        if condition.offline || condition.constrained { return nil }
        return condition.isRelay ? 1 * 1024 * 1024 : 5 * 1024 * 1024
    case .video, .audio:
        // Never automatic: there is no stream to cap. G11 sets the poster bound.
        return nil
    }
}
