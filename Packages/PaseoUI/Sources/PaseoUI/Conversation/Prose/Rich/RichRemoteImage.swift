#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

// MARK: - Images (§1.3–§1.5)

/// A remote image URL (H5 §2). One shared loader, one card.
///
/// E3 §3.5 stays: full width, the image's own aspect ratio, capped at 60 % of the container
/// height. What changed is everything behind that:
///
/// - the loader keeps the decoded image and its shape, so scrolling back draws it on the first
///   frame — no placeholder, no re-download, no layout shift;
/// - the box is reserved from the known aspect ratio before the bytes land, and the single
///   change from the 4:3 guess to the real ratio is animated with `Motion.disclosure`;
/// - a row that scrolls away mid-load does not end in a broken card: the fetch finishes into
///   the cache and the card is instant when it returns;
/// - failure says what happened and offers Retry and Open link, instead of a bare URL string.
struct RichRemoteImage: View {
    let urlString: String
    let alt: String
    /// The parsed link, once. `MediaPipeline.target(for:)` trims and parses (with a
    /// percent-encoding fallback), and a `data:` URL can be megabytes: body must not repeat it.
    private let target: URL?

    @State private var image: UIImage?
    /// Known before the pixels: from the cache, or from the image once it lands.
    @State private var aspectRatio: CGFloat?
    @State private var failure: MediaFailure?
    /// True while this card is the one that showed the placeholder: its failure then keeps the
    /// reserved box instead of collapsing to a 56 pt row and pulling the rest of the turn up.
    @State private var keepsFailureBox: Bool
    @State private var width: CGFloat = 0
    @State private var retryToken = 0
    /// The URL the state above belongs to. SwiftUI can hand this view a different block; when it
    /// does, the old picture must not be drawn for the new link.
    @State private var stateURL: String?
    @Namespace private var zoom
    /// The last streaming progress, for the determinate ring in place. Nil before the first
    /// progress event (or when the total is unknown): the indeterminate spinner instead.
    @State private var downloadProgress: Double?
    @Environment(\.richActions) private var richActions
    @State private var showViewer = false
    /// The container's height, for the 60 % cap, known before the first frame (`RichViewport`).
    @Environment(\.richViewportHeight) private var viewportHeight
    /// The prose column, published once by the transcript: the slot's width before any pixel.
    @Environment(\.richProseWidth) private var proseWidth
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(urlString: String, alt: String) {
        self.urlString = urlString
        self.alt = alt
        let target = MediaPipeline.target(for: urlString)
        self.target = target
        // First frame: whatever the session already knows about this URL. A cache read is
        // O(1), so the row has no "empty" frame to flash when it scrolls back.
        let seed = Self.seed(for: urlString, target: target)
        _image = State(initialValue: seed.image)
        _aspectRatio = State(initialValue: seed.aspectRatio)
        _failure = State(initialValue: seed.failure)
        _keepsFailureBox = State(initialValue: seed.keepsBox)
    }

    /// What the caches say about a URL before anything is drawn.
    private struct Seed {
        let image: UIImage?
        let aspectRatio: CGFloat?
        let failure: MediaFailure?
        /// A card that has not drawn the placeholder (a cache hit) may show the compact failure
        /// row; one that has must keep its box so nothing under it moves.
        let keepsBox: Bool
    }

    private static func seed(for urlString: String, target: URL?) -> Seed {
        // The same identity `MediaPipeline.cacheIdentity(for:)` computes, from the parsed link.
        let identity = target?.absoluteString ?? urlString
        let cached = MediaPipeline.cached(for: identity)
        let memo = MediaPipeline.cachedFailure(for: identity)
        let image = cached?.image
        return Seed(
            image: image,
            aspectRatio: cached?.aspectRatio ?? MediaMetadataCache.aspectRatio(for: identity),
            failure: image == nil ? memo : nil,
            keepsBox: image == nil && memo == nil)
    }

    private var heightCap: CGFloat { viewportHeight * 0.6 }

    /// The width of the image slot: the prose column when the transcript published one, else
    /// this card's own measurement (the file viewer and previews). Never the image's pixel size.
    private var slotWidth: CGFloat { proseWidth > 1 ? proseWidth : width }

    /// The ratio the box reserves: the image's own when we know it, else the old 4:3 guess.
    private var reservedAspect: CGFloat { aspectRatio ?? 4.0 / 3.0 }

    /// The §12 verdict for this card, O(1) in the environment's condition (R-1). Images always
    /// load on every link (user directive); only offline changes it, to `.cacheOnly`.
    private var policy: MediaFetchPolicy {
        mediaFetchPolicy(
            kind: .remoteImage, knownBytes: nil,
            condition: richActions?.linkCondition ?? .assumed)
    }

    private var fileName: String {
        let name = target?.lastPathComponent ?? ""
        return name.isEmpty ? "image" : name
    }

    private var host: String? {
        target?.host
    }

    /// Only an http(s) link is worth sending to Safari; a `data:` or `blob:` one is not.
    private var webURL: URL? {
        guard let url = target else { return nil }
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https" ? url : nil
    }

    /// One load per (URL, pixel bucket, retry, offline). The offline flag is part of the key so
    /// a card that stopped at "No connection" loads by itself when the connection returns.
    /// Nothing here runs per scroll frame.
    private var loadKey: String {
        let bucket = MediaSizing.pixelWidth(points: width, scale: displayScale)
        return "\(urlString)|\(bucket)|\(retryToken)|\(policy == .cacheOnly)"
    }

    /// What the card's box is doing, as one value: a placeholder at a reserved ratio, the image
    /// at its own, or a failure that either keeps the box or is compact. Motion runs only when
    /// this changes.
    private struct Layout: Equatable {
        let aspectRatio: CGFloat
        let stage: Int
    }

    private var layout: Layout {
        var stage = 0
        if image != nil {
            stage = 2
        } else if failure != nil {
            stage = keepsFailureBox ? 3 : 1
        }
        return Layout(aspectRatio: reservedAspect, stage: stage)
    }

    var body: some View {
        stage
            .frame(maxWidth: .infinity)
            .background { widthReader }
            .animation(
                Motion.disclosure.resolved(reduceMotion: reduceMotion),
                value: layout)
            .task(id: loadKey) { await load() }
            .fullScreenCover(isPresented: $showViewer) {
                MediaViewerView(
                    items: [viewerItem],
                    sourceID: viewerSourceID,
                    namespace: zoom,
                    onClose: { showViewer = false },
                    selection: .constant(0))
            }
            .paseoFeedback(.light, trigger: retryToken)
    }

    @ViewBuilder private var stage: some View {
        if let image {
            Button(action: openViewer) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .mediaSlot(width: slotWidth, heightCap: heightCap)
                    .background(Palette.codeSurface)
                    .clipShape(.rect(cornerRadius: Radius.md))
                    .overlay(alignment: .bottomTrailing) {
                        if showsAnimationBadge {
                            Text(target?.pathExtension.uppercased() ?? "GIF")
                                .font(.paseo(.codeCaption))
                                .foregroundStyle(Palette.onMediaBadge)
                                .padding(.horizontal, Metrics.badgeHPadding)
                                .padding(.vertical, Metrics.badgeVPadding)
                                .background(Palette.mediaBadge, in: .capsule)
                                .padding(Space.sm)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: viewerSourceID, in: zoom)
            .accessibilityLabel(alt.isEmpty ? "Image" : alt)
            .accessibilityHint("Opens the image full screen")
            // A context menu is the only way to the link without a second gesture language.
            // Share and Save to Photos live in the viewer (G3 §4.6).
            .paseoCardMenu(
                copyTitle: "Copy link",
                copyText: webURL != nil ? urlString : nil,
                externalTitle: "Open link",
                externalURL: webURL)
        } else if let failure {
            // Two forms, one behaviour: a card that showed the placeholder keeps the
            // placeholder's height, a card that was created already failed takes the compact row.
            if keepsFailureBox {
                MediaFailureBox(aspect: reservedAspect, width: slotWidth, heightCap: heightCap) {
                    failureContent(failure)
                }
            } else {
                PaseoCard(content:
                    failureContent(failure)
                        .frame(maxWidth: .infinity, alignment: .leading))
            }
        } else {
            MediaPlaceholder(
                aspect: reservedAspect, width: slotWidth, heightCap: heightCap,
                progress: downloadProgress, alt: alt)
        }
    }

    private func failureContent(_ failure: MediaFailure) -> some View {
        MediaFailureContent(
            detail: detail(for: failure), onRetry: retry, webURL: webURL, host: host)
    }

    private func openViewer() {
        showViewer = true
    }

    /// The zoom-transition source, stable per card: the thumbnail the viewer returns to.
    private var viewerSourceID: String { "image:\(urlString)" }

    /// One viewer page: the pixels on screen now, the full fetch behind them (G3 §4.6).
    private var viewerItem: MediaViewerItem {
        MediaViewerItem(
            id: urlString,
            thumbnail: image,
            fullSource: target.map(MediaSource.remote),
            fileName: fileName,
            alt: alt.isEmpty ? fileName : alt,
            filePath: nil)
    }

    /// The transcript shows the first frame; only the viewer animates (G3 §4.6).
    private var showsAnimationBadge: Bool {
        let ext = target?.pathExtension.lowercased()
        return ext == "gif" || ext == "apng"
    }

    /// "host · what happened", the one line the card has room for.
    private func detail(for failure: MediaFailure) -> String {
        guard let host else { return failure.message }
        return "\(host) · \(failure.message)"
    }

    /// The card's inner width, for decoding at the size it will be drawn at. Published only
    /// when it actually changes — never per scroll frame.
    private var widthReader: some View {
        // `onGeometryChange` on the clear background instead of a `GeometryReader` per card (W1): same
        // size, delivered at once and on change, written only when it differs.
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if width != newWidth { width = newWidth }
            }
    }

    private func retry() {
        failure = nil
        downloadProgress = nil
        // A retry shows the placeholder again, so a second failure must keep its box.
        keepsFailureBox = true
        retryToken += 1
    }

    @MainActor
    private func load() async {
        if stateURL != urlString { adoptState(for: urlString) }
        // No width yet: a fetch at a guessed size would only be thrown away.
        guard width > 1 else { return }
        // Offline fails closed: no fetch. A picture another card already loaded this session
        // still shows; otherwise the offline failure does, and the connection returning
        // reruns this task.
        if policy == .cacheOnly {
            if image == nil,
                let cached = MediaPipeline.cached(for: MediaPipeline.cacheIdentity(for: urlString))
            {
                image = cached.image
                aspectRatio = cached.aspectRatio
                failure = nil
            }
            if image == nil, failure == nil { failure = .offline }
            return
        }
        if failure == .offline {
            // Back online: the placeholder replaces the offline failure while it loads.
            failure = nil
            keepsFailureBox = true
        }
        guard let url = target else {
            failure = .badURL
            return
        }
        let pixelWidth = MediaSizing.pixelWidth(points: width, scale: displayScale)
        let ignoresFailureCache = retryToken > 0
        for await event in await MediaPipeline.shared.events(
            source: .remote(url), pixelWidth: pixelWidth,
            ignoreFailureCache: ignoresFailureCache)
        {
            // The row may have gone; the pipeline already cached the result for its return.
            guard !Task.isCancelled else { return }
            switch event {
            case .size(let size):
                // The probe's true ratio wins only while nothing is known: one settle, once.
                if aspectRatio == nil, size.height > 0 {
                    aspectRatio = size.width / size.height
                }
            case .progress(let fraction):
                downloadProgress = fraction
            case .final(let outcome):
                downloadProgress = nil
                switch outcome {
                case .image(let payload):
                    image = payload.image
                    aspectRatio = payload.aspectRatio
                    failure = nil
                case .svg(let source, let knownAspect):
                    await renderSVG(source, knownAspect: knownAspect)
                case .failure(let reason):
                    failure = reason
                }
            }
        }
    }

    /// Point the card at a URL it has not drawn yet, starting from whatever is cached.
    private func adoptState(for urlString: String) {
        stateURL = urlString
        let seed = Self.seed(for: urlString, target: target)
        image = seed.image
        aspectRatio = seed.aspectRatio
        failure = seed.failure
        keepsFailureBox = seed.keepsBox
        downloadProgress = nil
    }

    /// SVG has no `UIImage` decoder; the shared offscreen `WKWebView` draws it instead, at the
    /// card's width, and its `viewBox` reserves the box while that happens.
    @MainActor
    private func renderSVG(_ source: String, knownAspect: CGFloat?) async {
        let identity = MediaPipeline.cacheIdentity(for: urlString)
        if let knownAspect {
            aspectRatio = knownAspect
            MediaMetadataCache.remember(knownAspect, for: identity)
        }
        guard
            let rendered = await RichSVGImageRender.image(
                source: source, width: width, scale: displayScale, dark: colorScheme == .dark)
        else {
            // A render skipped because the card scrolled away is not a decoding failure.
            if !Task.isCancelled { failure = .decoding }
            return
        }
        guard !Task.isCancelled else { return }
        image = rendered
        let size = rendered.size
        let ratio = size.height > 0 ? size.width / size.height : 1
        aspectRatio = ratio
        MediaMetadataCache.remember(ratio, for: identity)
    }
}
#endif
