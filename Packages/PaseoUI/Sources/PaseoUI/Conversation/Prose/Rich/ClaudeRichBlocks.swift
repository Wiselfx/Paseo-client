#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// Routes one detector block to its renderer, in document order (the caller iterates).
/// Actions and the workspace image loader arrive from `RichActions` in the environment (G1
/// §1.2, R-2): this router and every card below it take values only.
struct ClaudeRichBlockView: View {
    let block: RichContentBlock

    var body: some View {
        switch block {
        case .linkCard(let url, _):
            RichLinkCard(url: url)
        case .youTubePlayer(let reference, _):
            YouTubeRichCard(reference: reference, full: true)
        case .youTubeInline(let reference, _):
            YouTubeRichCard(reference: reference, full: false)
        case .bareImageURL(let url, _):
            RichRemoteImage(urlString: url, alt: "")
        case .localImage(let path, let alt, _):
            RichLocalImage(path: path, alt: alt)
        case .localFileLink(let path, _):
            RichPathChip(path: path, glyph: "doc.text")
        case .rawSVG(let source, _):
            RichSVGCard(code: source)
        case .visualize(let code, _):
            RichWebCard(code: code)
        case .mapCard(let reference, _):
            RichMapCard(reference: reference)
        }
    }
}

// MARK: - Map card (M17)

/// Snapshot cache, keyed by coordinate. Snapshots are single-pass renders; re-snapshot
/// on every scroll would flicker, so the card never refetches what it already drew.
@MainActor
enum RichMapSnapshotCache {
    private static var table: [String: UIImage] = [:]

    static func image(for reference: MapReference) -> UIImage? {
        guard let lat = reference.latitude, let lng = reference.longitude else { return nil }
        return table["\(lat),\(lng)"]
    }

    static func store(_ image: UIImage, for reference: MapReference) {
        guard let lat = reference.latitude, let lng = reference.longitude else { return }
        if table.count >= 32 { table.removeAll(keepingCapacity: true) }
        table["\(lat),\(lng)"] = image
    }
}

/// A calm MapKit snapshot (no live map in the transcript) that opens Apple Maps on tap.
struct RichMapCard: View {
    let reference: MapReference

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: UIImage?

    private var targetURL: URL? {
        if let lat = reference.latitude, let lng = reference.longitude {
            return URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)")
        }
        return URL(string: reference.url)
    }

    /// The 150 pt snapshot slot, edge to edge in the media card; the container clips it.
    private var snapshotBox: some View {
        ZStack {
            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Palette.codeSurface)
                    .overlay {
                        Image(systemName: "map")
                            .font(.glyph(.xlarge, weight: .light))
                            .foregroundStyle(Palette.secondaryInk)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .contentShape(.rect)
    }

    var body: some View {
        Button {
            if let targetURL { openURL(targetURL) }
        } label: {
            PaseoMediaCard(
                media: snapshotBox,
                header: PaseoCardHeader(glyph: "mappin", title: caption))
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .paseoCardMenu(
            openTitle: "Open in Maps",
            onOpen: { if let targetURL { openURL(targetURL) } },
            copyTitle: "Copy location",
            copyText: caption)
        .paseoCardAccessibility(kind: "Map", title: caption, isButton: true)
        .accessibilityHint("Opens Apple Maps")
        .task(id: "\(reference.latitude ?? 0),\(reference.longitude ?? 0)") {
            guard snapshot == nil, let lat = reference.latitude, let lng = reference.longitude else { return }
            if let cached = RichMapSnapshotCache.image(for: reference) {
                snapshot = cached
                return
            }
            snapshot = await Self.snapshot(lat: lat, lng: lng)
            if let snapshot {
                RichMapSnapshotCache.store(snapshot, for: reference)
            }
        }
    }

    private var caption: String {
        if let lat = reference.latitude, let lng = reference.longitude {
            return "\(lat), \(lng)"
        }
        return RichContentDetector.displayURL(reference.url)
    }

    /// One static render of a 300×180 region around the point. Calm, and cached.
    private static func snapshot(lat: Double, lng: Double) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04))
        options.size = CGSize(width: 600, height: 360)
        options.showsBuildings = false
        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            return snapshot.image
        } catch {
            return nil
        }
    }
}

// MARK: - Link card (§1.1)

/// Metadata cache, keyed by URL. LPMetadataProvider network fetches are expensive; a
/// card should never refetch what scroll already showed it.
@MainActor
enum RichLinkMetadataCache {
    private static var table: [URL: LPLinkMetadata] = [:]

    static func metadata(for url: URL) -> LPLinkMetadata? { table[url] }

    static func store(_ metadata: LPLinkMetadata, for url: URL) {
        if table.count >= 64 { table.removeAll(keepingCapacity: true) }
        table[url] = metadata
    }
}

struct RichLinkCard: View {
    let url: String

    @State private var metadata: LPLinkMetadata?
    @State private var showSafari = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            showSafari = true
        } label: {
            PaseoCard(content:
                HStack(alignment: .center, spacing: 10) {
                    if let metadata {
                        LinkPreviewView(metadata: metadata)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        placeholder
                    }
                }
                .contentShape(.rect))
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .paseoCardMenu(
            openTitle: "Open",
            onOpen: { showSafari = true },
            copyTitle: "Copy link",
            copyText: url,
            externalTitle: "Open in Safari",
            externalURL: URL(string: url))
        .paseoCardAccessibility(
            kind: "Link",
            title: RichContentDetector.domain(for: url),
            meta: RichContentDetector.displayURL(url),
            isButton: true)
        .task(id: url) {
            guard let parsed = URL(string: url) else { return }
            if let cached = RichLinkMetadataCache.metadata(for: parsed) {
                metadata = cached
                return
            }
            if let fetched = try? await Self.fetchMetadata(for: parsed) {
                RichLinkMetadataCache.store(fetched, for: parsed)
                metadata = fetched
            }
        }
        .fullScreenCover(isPresented: $showSafari) {
            if let target = URL(string: url) {
                SafariView(url: target).ignoresSafeArea()
            }
        }
    }

    private var placeholder: some View {
        placeholderCard
    }

    /// LPMetadataProvider only documents the completion-handler API; bridging keeps the
    /// async call site without relying on an undocumented async variant.
    private static func fetchMetadata(for url: URL) async throws -> LPLinkMetadata {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MetadataBox, Error>) in
            LPMetadataProvider().startFetchingMetadata(for: url) { metadata, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let metadata else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                continuation.resume(returning: MetadataBox(value: metadata))
            }
        }.value
    }

    /// `LPLinkMetadata` isn't `Sendable`; the provider hands over a finished object that
    /// nothing mutates afterwards, so it is safe to carry across the completion hop.
    private struct MetadataBox: @unchecked Sendable {
        let value: LPLinkMetadata
    }

    private var placeholderCard: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.chip)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "link")
                        .font(.glyph(.regular))
                        .foregroundStyle(Palette.secondaryInk)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(RichContentDetector.domain(for: url))
                    .font(.paseo(.footnote, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(RichContentDetector.displayURL(url))
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// `LPLinkView` in SwiftUI. Height clamp: LPLinkView self-sizes to its metadata, which for
/// rich media can be tall; the card clips at 160 pt instead of letting one link eat the
/// transcript.
struct LinkPreviewView: UIViewRepresentable {
    let metadata: LPLinkMetadata

    func makeUIView(context: Context) -> LPLinkView {
        LPLinkView(metadata: metadata)
    }

    func updateUIView(_ uiView: LPLinkView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LPLinkView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: min(max(size.height, 1), 160))
    }
}

// MARK: - YouTube (§1.2)

/// One inline player at a time across the transcript (E3 §3.4). Switching the active id rebuilds
/// the previous card without its web view, which tears the player down and stops playback.
@MainActor
@Observable
final class InlineYouTubePlayback {
    static let shared = InlineYouTubePlayback()
    var activeID: String?
}

/// Thumbnail card at 16:9, full width; tapping swaps it in place for an inline player. The web
/// view is created by the tap, never for every card, and is destroyed when the card scrolls away.
/// "Open in YouTube" in the context menu keeps the old external path.
struct YouTubeRichCard: View {
    let reference: YouTubeReference
    let full: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.displayScale) private var displayScale

    /// The 16:9 card's still. Decoded once through the shared loader and cached by URL, so
    /// scrolling past and back does not re-download or re-flash it (H5 round 2: this used to be
    /// an uncached system image view, the same defect the image cards had).
    @State private var still: UIImage?
    @State private var stillFailed = false
    /// The card's real width, measured once per layout so the still is decoded at the size it
    /// is drawn at (never a guessed 320/430 pt).
    @State private var width: CGFloat = 0

    private let playback = InlineYouTubePlayback.shared
    private var isPlaying: Bool { playback.activeID == reference.id }

    /// One decode per (URL, pixel bucket). Nil while playing — the player covers the still —
    /// and until the width is known.
    private var stillKey: String? {
        guard !isPlaying, width > 1 else { return nil }
        let pixels = MediaSizing.pixelWidth(points: width, scale: displayScale)
        return "\(RichContentDetector.youTubeThumbnailURL(id: reference.id))|\(pixels)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if isPlaying {
                    InlineYouTubePlayer(referenceID: reference.id)
                        .accessibilityLabel("YouTube video \(reference.id)")
                        .transition(.opacity)
                } else {
                    thumbnail
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: full ? .infinity : 320, alignment: .leading)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background { widthReader }
            .background(Color.black)
            .clipShape(.rect(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
            }
            .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: isPlaying)
            .onScrollVisibilityChange(threshold: 0.05) { visible in
                // Far enough off screen: destroy the player rather than let audio keep running.
                if !visible, isPlaying { playback.activeID = nil }
            }
            if full {
                HStack(spacing: 6) {
                    Image(systemName: "play")
                        .font(.glyph(.small, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                    Text("youtube.com · \(reference.id)")
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isPlaying {
                        Button("Close") { playback.activeID = nil }
                            .font(.paseo(.caption, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: full ? .infinity : 320, alignment: .leading)
    }

    private var thumbnail: some View {
        ZStack {
            if let still {
                Image(uiImage: still)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Palette.codeSurface)
                    .overlay {
                        if stillFailed {
                            Image(systemName: "photo")
                                .font(.glyph(.xlarge, weight: .light))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
            }

            Circle()
                .fill(.black.opacity(0.55))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.glyph(.regular, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 1)
                }
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .onTapGesture { playback.activeID = reference.id }
        .contextMenu {
            Button("Open in YouTube", systemImage: "play.rectangle") { openInYouTube() }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Play YouTube video \(reference.id)")
        // The box is already reserved by the card's 16:9 frame, so the still can land whenever.
        .task(id: stillKey) { await loadStill() }
    }

    /// The card's inner width, measured on the frame it is actually drawn in. Published only
    /// when it changes; nothing here runs per scroll frame.
    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
        }
    }

    /// One decode per URL, through the same loader (and cache) as every other remote image.
    /// A failed thumbnail is a decorative miss, not an error worth a card.
    @MainActor
    private func loadStill() async {
        guard width > 1, still == nil else { return }
        let url = RichContentDetector.youTubeThumbnailURL(id: reference.id)
        let outcome = await MediaPipeline.shared.load(
            urlString: url,
            pixelWidth: MediaSizing.pixelWidth(points: width, scale: displayScale))
        guard !Task.isCancelled else { return }
        switch outcome {
        case .image(let payload): still = payload.image
        case .failure: stillFailed = true
        case .svg: stillFailed = true
        }
    }

    private func openInYouTube() {
        if let target = URL(string: RichContentDetector.youTubeWatchURL(id: reference.id)) {
            openURL(target)
        }
    }
}

/// The inline player (E3 §3.4): `youtube-nocookie.com` embed in a one-line document whose
/// `baseURL` is an https origin, so YouTube sees a referrer (without one it refuses with error
/// 152/153). Inline playback, no gesture required to start, no page scroll.
struct InlineYouTubePlayer: UIViewRepresentable {
    let referenceID: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(Self.document(for: referenceID), baseURL: Self.origin)
        context.coordinator.loadedOrigin = Self.origin
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Leaving the hierarchy would usually be enough; stopping the load and dropping the
        // delegate makes sure the media session ends with the view.
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.pauseAllMediaPlayback {}
    }

    /// The referrer origin YouTube expects; the document itself is inline HTML.
    static let origin = URL(string: "https://www.youtube-nocookie.com")

    static func document(for id: String) -> String {
        // An id is alphanumerics plus `-`/`_`; anything else is dropped before it reaches markup.
        let embedID = id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return """
            <!DOCTYPE html><html><head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}
            iframe{border:0;display:block;width:100%;height:100%}</style>
            </head><body>
            <iframe src="https://www.youtube-nocookie.com/embed/\(embedID)?playsinline=1&autoplay=1&rel=0&modestbranding=1"
              allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
              allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>
            </body></html>
            """
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedOrigin: URL?

        /// The document load is allowed; a main-frame navigation away from it (YouTube's own
        /// "Watch on YouTube") is cancelled — the card's menu opens the app instead.
        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let frame = navigationAction.targetFrame, frame.isMainFrame else { return .allow }
            if navigationAction.navigationType == .other, loadedOrigin != nil { return .allow }
            return .cancel
        }
    }
}

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

    @State private var image: UIImage?
    /// Known before the pixels: from the cache, or from the image once it lands.
    @State private var aspectRatio: CGFloat?
    @State private var failure: MediaFailure?
    /// True while this card is the one that showed the placeholder: its failure then keeps the
    /// reserved box instead of collapsing to a 56 pt row and pulling the rest of the turn up.
    @State private var keepsFailureBox = true
    @State private var width: CGFloat = 0
    @State private var retryToken = 0
    /// The URL the state above belongs to. SwiftUI can hand this view a different block; when it
    /// does, the old picture must not be drawn for the new link.
    @State private var stateURL: String?
    @Namespace private var zoom
    /// Set once the reader explicitly taps (or retries): the policy gate and the in-flight
    /// ceiling stop applying — an explicit fetch is always honored.
    @State private var tappedLoad = false
    /// The last streaming progress, for the determinate ring in place. Nil before the first
    /// progress event (or when the total is unknown): the indeterminate spinner instead.
    @State private var downloadProgress: Double?
    /// The bytes the last `.tooLarge` learned, for the tap-to-download size line.
    @State private var tooLargeBytes: Int64?
    @Environment(\.richActions) private var richActions
    @State private var showViewer = false
    /// The container's height, for the 60 % cap, known before the first frame (`RichViewport`).
    @Environment(\.richViewportHeight) private var viewportHeight
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    init(urlString: String, alt: String) {
        self.urlString = urlString
        self.alt = alt
        // First frame: whatever the session already knows about this URL. A cache read is
        // O(1), so the row has no "empty" frame to flash when it scrolls back.
        let seed = Self.seed(for: urlString)
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

    private static func seed(for urlString: String) -> Seed {
        let identity = MediaPipeline.cacheIdentity(for: urlString)
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

    /// The ratio the box reserves: the image's own when we know it, else the old 4:3 guess.
    private var reservedAspect: CGFloat { aspectRatio ?? 4.0 / 3.0 }

    /// The §12 verdict for this card, O(1) in the environment's condition (R-1). Unknown size
    /// proceeds optimistically on cheap links; the streaming cap enforces the ceiling and the
    /// card flips to tap-to-download with the learned size.
    private var policy: MediaFetchPolicy {
        mediaFetchPolicy(
            kind: .remoteImage, knownBytes: nil,
            condition: richActions?.linkCondition ?? .assumed)
    }

    /// The in-flight ceiling, from the same table. Nil once the reader taps: their fetch.
    private var capBytes: Int64? {
        guard !tappedLoad else { return nil }
        return mediaDownloadCap(
            kind: .remoteImage, condition: richActions?.linkCondition ?? .assumed)
    }

    /// The reserved box with a download action instead of bytes (§12): the policy said wait
    /// and the reader has not tapped yet, or a stream hit the ceiling before any attempt.
    /// After an explicit tap the failure box (with Retry) owns the error — the box must
    /// never loop tap → fail → tap on a file the ceiling will always refuse. `.cacheOnly`
    /// (offline) is not tappable — it shows the offline failure instead.
    private var showsTapBox: Bool {
        guard image == nil, !tappedLoad else { return false }
        if let failure {
            if case .tooLarge = failure { return true }
            return false
        }
        return policy == .tapToDownload
    }

    private var fileName: String {
        MediaPipeline.target(for: urlString)?.lastPathComponent.nilIfEmpty ?? "image"
    }

    private var host: String? {
        MediaPipeline.target(for: urlString)?.host
    }

    /// Only an http(s) link is worth sending to Safari; a `data:` or `blob:` one is not.
    private var webURL: URL? {
        guard let url = MediaPipeline.target(for: urlString) else { return nil }
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https" ? url : nil
    }

    /// One load per (URL, pixel bucket, retry). Nothing here runs per scroll frame.
    private var loadKey: String {
        "\(urlString)|\(MediaSizing.pixelWidth(points: width, scale: displayScale))|\(retryToken)"
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
        } else if showsTapBox {
            stage = 4
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
    }

    @ViewBuilder private var stage: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: heightCap)
                .background(Palette.codeSurface)
                .clipShape(.rect(cornerRadius: Radius.md))
                .overlay(alignment: .bottomTrailing) {
                    if showsAnimationBadge {
                        Text(MediaPipeline.target(for: urlString)?.pathExtension.uppercased() ?? "GIF")
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
                .matchedTransitionSource(id: viewerSourceID, in: zoom)
                .onTapGesture {
                    showViewer = true
                }
                .accessibilityLabel(alt.isEmpty ? "Image" : alt)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the image full screen")
                // A context menu is the only way to the link without a second gesture language.
                // Share and Save to Photos live in the viewer (G3 §4.6).
                .paseoCardMenu(
                    copyTitle: "Copy link",
                    copyText: webURL != nil ? urlString : nil,
                    externalTitle: "Open link",
                    externalURL: webURL)
        } else if showsTapBox {
            tapBox
        } else if let failure {
            if keepsFailureBox {
                boxedFailure(failure)
            } else {
                compactFailure(failure)
            }
        } else {
            placeholder
        }
    }

    /// The §12 tap state: the reserved box, a centered download glyph, the size when known,
    /// the file name. One tap fetches it, with the progress ring in the same frame. The box
    /// never changes size through any of this — only its inside crossfades (`Motion.fade`).
    private var tapBox: some View {
        Button {
            startTappedLoad()
        } label: {
            Rectangle()
                .fill(Palette.codeSurface)
                .aspectRatio(reservedAspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: heightCap)
                .clipShape(.rect(cornerRadius: Radius.md))
                .overlay {
                    VStack(spacing: Space.sm) {
                        if let progress = downloadProgress {
                            ProgressView(value: progress)
                                .controlSize(.small)
                                .tint(Palette.secondaryInk)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .font(.glyph(.large, weight: .light))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        Text(tapLabel)
                            .font(.paseo(.caption, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(fileName)
                            .font(.paseo(.codeCaption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, Space.md)
                }
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .paseoCardAccessibility(
            kind: "Image", title: alt.isEmpty ? fileName : alt, isButton: true)
        .accessibilityHint("Downloads the image")
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    /// "Tap to download", plus the size when the ceiling learned it (§15, new copy).
    private var tapLabel: String {
        guard let bytes = tooLargeBytes else { return "Tap to download" }
        return "Tap to download · \(Self.byteFormatter.string(fromByteCount: bytes))"
    }

    private func startTappedLoad() {
        Haptics.light()
        tappedLoad = true
        failure = nil
        tooLargeBytes = nil
        downloadProgress = nil
        keepsFailureBox = true
        retryToken += 1
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Palette.codeSurface)
            .aspectRatio(reservedAspect, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: heightCap)
            .clipShape(.rect(cornerRadius: Radius.md))
            .overlay {
                // Streaming with a known total: the determinate ring in the same frame.
                if let progress = downloadProgress {
                    ProgressView(value: progress)
                        .controlSize(.small)
                        .tint(Palette.secondaryInk)
                } else {
                    ProgressView().controlSize(.small).tint(Palette.secondaryInk)
                }
            }
            .accessibilityLabel(alt.isEmpty ? "Loading image" : "Loading image: \(alt)")
    }

    /// What went wrong, in the user's words, with the two things worth doing about it.
    ///
    /// Two forms, one behaviour: a card that showed the placeholder keeps the placeholder's
    /// height (H5 round 2 review — a 270 pt box must not collapse to 56 pt under the reader),
    /// a card that was created already failed takes the compact row.
    private func boxedFailure(_ failure: MediaFailure) -> some View {
        Rectangle()
            .fill(Palette.codeSurface)
            .aspectRatio(reservedAspect, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: heightCap)
            .clipShape(.rect(cornerRadius: Radius.md))
            .overlay {
                failureContent(failure)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
            }
    }

    private func compactFailure(_ failure: MediaFailure) -> some View {
        PaseoCard(content:
            failureContent(failure)
                .frame(maxWidth: .infinity, alignment: .leading))
    }

    private func failureContent(_ failure: MediaFailure) -> some View {
        HStack(alignment: .center, spacing: Space.sm) {
            Image(systemName: "photo")
                .font(.glyph(.large, weight: .light))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Couldn't load image")
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(detail(for: failure))
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Space.sm)
            Button("Retry") { retry() }
                .buttonStyle(.plain)
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(minWidth: Metrics.hitSize, minHeight: Metrics.hitSize)
                .accessibilityLabel("Try loading the image again")
            if webURL != nil {
                Button {
                    if let webURL { openURL(webURL) }
                } label: {
                    Image(systemName: "safari")
                        .font(.glyph(.small))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open link")
                .accessibilityHint("Opens \(host ?? "the link") in Safari")
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The zoom-transition source, stable per card: the thumbnail the viewer returns to.
    private var viewerSourceID: String { "image:\(urlString)" }

    /// One viewer page: the pixels on screen now, the full fetch behind them (G3 §4.6).
    private var viewerItem: MediaViewerItem {
        MediaViewerItem(
            id: urlString,
            thumbnail: image,
            fullSource: MediaPipeline.target(for: urlString).map(MediaSource.remote),
            fileName: fileName,
            alt: alt.isEmpty ? fileName : alt,
            filePath: nil)
    }

    /// The transcript shows the first frame; only the viewer animates (G3 §4.6).
    private var showsAnimationBadge: Bool {
        let ext = MediaPipeline.target(for: urlString)?.pathExtension.lowercased()
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
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
        }
    }

    private func retry() {
        Haptics.light()
        // An explicit retry is the reader's fetch: the gate and the ceiling stop applying.
        tappedLoad = true
        failure = nil
        tooLargeBytes = nil
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
        // The §12 gate: a metered link waits for the tap box, offline fails closed. A tap,
        // a retry, or a cached image skips the gate — none of them spends the reader's data.
        if !tappedLoad {
            switch policy {
            case .tapToDownload: return
            case .cacheOnly:
                if image == nil, failure == nil { failure = .offline }
                return
            case .automatic: break
            }
        }
        guard let url = MediaPipeline.target(for: urlString) else {
            failure = .badURL
            return
        }
        let pixelWidth = MediaSizing.pixelWidth(points: width, scale: displayScale)
        let ignoresFailureCache = retryToken > 0
        for await event in await MediaPipeline.shared.events(
            source: .remote(url), pixelWidth: pixelWidth, capBytes: capBytes,
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
                    if case .tooLarge(let bytes) = reason { tooLargeBytes = bytes }
                    failure = reason
                }
            }
        }
    }

    /// Point the card at a URL it has not drawn yet, starting from whatever is cached.
    private func adoptState(for urlString: String) {
        stateURL = urlString
        let seed = Self.seed(for: urlString)
        image = seed.image
        aspectRatio = seed.aspectRatio
        failure = seed.failure
        keepsFailureBox = seed.keepsBox
        tappedLoad = false
        downloadProgress = nil
        tooLargeBytes = nil
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
        let dark = colorScheme == .dark
        let html = RichHTMLDocument.rawSVG(source: source, dark: dark)
        guard
            let rendered = await RichSnapshotQueue.shared.snapshot(
                html: html, width: width, scale: displayScale)
        else {
            failure = .decoding
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

/// A bare local path to an image, read through the daemon via `RichActions` (G1 §1.2).
/// Without a reachable store — or on any read failure — this falls back to `RichPathChip`.
struct RichLocalImage: View {
    let path: String
    let alt: String

    @Environment(\.richActions) private var richActions
    @State private var image: UIImage?
    @State private var aspectRatio: CGFloat?
    @State private var failure: MediaFailure?
    @State private var keepsFailureBox = false
    @State private var tappedLoad = false
    @State private var retryToken = 0
    @State private var downloadProgress: Double?
    @State private var width: CGFloat = 0
    @State private var showViewer = false
    @Namespace private var zoom
    @Environment(\.richViewportHeight) private var viewportHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    private var heightCap: CGFloat { viewportHeight * 0.6 }

    private var fileName: String {
        (path as NSString).lastPathComponent.nilIfEmpty ?? "image"
    }

    /// The zoom-transition source, stable per card.
    private var viewerSourceID: String { "local-image:\(path)" }

    /// One viewer page: the pixels on screen now, the full fetch behind them, with Show in
    /// Files for the daemon path (G3 §4.6).
    private var viewerItem: MediaViewerItem {
        MediaViewerItem(
            id: "local-image:\(path)",
            thumbnail: image,
            fullSource: ref.map(MediaSource.daemon),
            fileName: fileName,
            alt: alt.isEmpty ? fileName : alt,
            filePath: ref == nil ? nil : path)
    }

    /// The daemon file, when the conversation names its workspace. Nil outside one
    /// (previews): the path chip is all there honestly is.
    private var ref: DaemonFileRef? {
        guard let workspaceID = richActions?.daemonWorkspaceID else { return nil }
        return DaemonFileRef(workspaceID: workspaceID, path: path, revision: nil)
    }

    /// The ratio the box reserves: the image's own when known, else the 4:3 guess.
    private var reservedAspect: CGFloat { aspectRatio ?? 4.0 / 3.0 }

    private var policy: MediaFetchPolicy {
        mediaFetchPolicy(
            kind: .daemonImage, knownBytes: nil,
            condition: richActions?.linkCondition ?? .assumed)
    }

    private var capBytes: Int64? {
        guard !tappedLoad else { return nil }
        return mediaDownloadCap(
            kind: .daemonImage, condition: richActions?.linkCondition ?? .assumed)
    }

    /// What the card's box is doing, as one value, so motion runs only when this changes.
    private struct Layout: Equatable {
        let aspectRatio: CGFloat
        let stage: Int
    }

    private var layout: Layout {
        var stage = 0
        if image != nil {
            stage = 2
        } else if showsTapBox {
            stage = 4
        } else if failure != nil {
            stage = keepsFailureBox ? 3 : 1
        }
        return Layout(aspectRatio: reservedAspect, stage: stage)
    }

    private var showsTapBox: Bool {
        guard image == nil, !tappedLoad else { return false }
        if let failure {
            if case .tooLarge = failure { return true }
            return false
        }
        return policy == .tapToDownload
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: heightCap)
                    .background(Palette.codeSurface)
                    .clipShape(.rect(cornerRadius: Radius.md))
                    .contentShape(.rect)
                    .matchedTransitionSource(id: viewerSourceID, in: zoom)
                    .onTapGesture {
                        showViewer = true
                    }
                    .accessibilityLabel(alt.isEmpty ? fileName : alt)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens the image full screen")
            } else if showsTapBox {
                tapBox
            } else if let failure {
                if keepsFailureBox {
                    boxedFailure(failure)
                } else {
                    RichPathChip(path: path, glyph: "photo")
                }
            } else {
                Rectangle()
                    .fill(Palette.codeSurface)
                    .aspectRatio(reservedAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: heightCap)
                    .clipShape(.rect(cornerRadius: Radius.md))
                    .overlay {
                        if let progress = downloadProgress {
                            ProgressView(value: progress)
                                .controlSize(.small)
                                .tint(Palette.secondaryInk)
                        } else {
                            ProgressView().controlSize(.small).tint(Palette.secondaryInk)
                        }
                    }
                    .accessibilityLabel(alt.isEmpty ? "Loading image" : "Loading image: \(alt)")
            }
        }
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
    }

    /// One load per (path, pixel bucket, tap, retry). Nothing here runs per scroll frame.
    private var loadKey: String {
        let bucket = MediaSizing.pixelWidth(points: width, scale: displayScale)
        return "\(path)|\(bucket)|\(tappedLoad)|\(retryToken)"
    }

    /// The card's inner width, for decoding at the size it will be drawn at. Published only
    /// when it actually changes — never per scroll frame.
    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
        }
    }

    /// The §12 tap state: the reserved box, the file name, one tap to fetch.
    private var tapBox: some View {
        Button {
            startTappedLoad()
        } label: {
            Rectangle()
                .fill(Palette.codeSurface)
                .aspectRatio(reservedAspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: heightCap)
                .clipShape(.rect(cornerRadius: Radius.md))
                .overlay {
                    VStack(spacing: Space.sm) {
                        Image(systemName: "arrow.down.circle")
                            .font(.glyph(.large, weight: .light))
                            .foregroundStyle(Palette.secondaryInk)
                        Text("Tap to download")
                            .font(.paseo(.caption, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(fileName)
                            .font(.paseo(.codeCaption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, Space.md)
                }
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .paseoCardAccessibility(kind: "Image", title: fileName, isButton: true)
        .accessibilityHint("Downloads the image")
    }

    /// The kept box with the failure line, like the remote card: the reader watched the
    /// placeholder, so the box stays and only the inside is honest. Retry refetches.
    private func boxedFailure(_ failure: MediaFailure) -> some View {
        Rectangle()
            .fill(Palette.codeSurface)
            .aspectRatio(reservedAspect, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: heightCap)
            .clipShape(.rect(cornerRadius: Radius.md))
            .overlay {
                HStack(alignment: .center, spacing: Space.sm) {
                    Image(systemName: "photo")
                        .font(.glyph(.large, weight: .light))
                        .foregroundStyle(Palette.secondaryInk)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Couldn't load image")
                            .font(.paseo(.caption, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(path)
                            .font(.paseo(.codeCaption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: Space.sm)
                    Button("Retry") { retry() }
                        .buttonStyle(.plain)
                        .font(.paseo(.caption, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(minWidth: Metrics.hitSize, minHeight: Metrics.hitSize)
                        .accessibilityLabel("Try loading the image again")
                }
                .padding(.horizontal, Space.md)
                .accessibilityElement(children: .contain)
            }
    }

    private func startTappedLoad() {
        Haptics.light()
        tappedLoad = true
        failure = nil
        keepsFailureBox = true
        downloadProgress = nil
    }

    private func retry() {
        Haptics.light()
        // An explicit retry is the reader's fetch: the gate and the ceiling stop applying.
        tappedLoad = true
        failure = nil
        keepsFailureBox = true
        downloadProgress = nil
        retryToken += 1
    }

    @MainActor
    private func load() async {
        guard let ref else {
            // No workspace (a preview): a chip was already drawn, nothing to load.
            return
        }
        guard width > 1 else { return }
        if !tappedLoad {
            switch policy {
            case .tapToDownload: return
            case .cacheOnly:
                if image == nil, failure == nil { failure = .offline }
                return
            case .automatic: break
            }
        }
        // The placeholder is on screen from here: a failure keeps its box.
        keepsFailureBox = true
        let pixelWidth = MediaSizing.pixelWidth(points: width, scale: displayScale)
        for await event in await MediaPipeline.shared.events(
            source: .daemon(ref), pixelWidth: pixelWidth, capBytes: capBytes,
            ignoreFailureCache: retryToken > 0,
            allowStaleDisk: policy == .cacheOnly)
        {
            guard !Task.isCancelled else { return }
            switch event {
            case .size(let size):
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
                    await renderDaemonSVG(source, knownAspect: knownAspect, ref: ref)
                case .failure(let reason):
                    failure = reason
                }
            }
        }
    }

    /// Daemon SVGs draw through the shared offscreen renderer, like remote ones.
    @MainActor
    private func renderDaemonSVG(_ source: String, knownAspect: CGFloat?, ref: DaemonFileRef) async {
        if let knownAspect {
            aspectRatio = knownAspect
            MediaMetadataCache.remember(knownAspect, for: MediaPipeline.liveKey(ref: ref))
        }
        let html = RichHTMLDocument.rawSVG(source: source, dark: colorScheme == .dark)
        guard
            let rendered = await RichSnapshotQueue.shared.snapshot(
                html: html, width: width, scale: displayScale)
        else {
            failure = .decoding
            return
        }
        guard !Task.isCancelled else { return }
        image = rendered
        let size = rendered.size
        if size.height > 0 { aspectRatio = size.width / size.height }
        failure = nil
    }
}

/// A mono path chip: for local image paths that can't be read, and for bare non-image
/// `file://` paths (§1.5). Tap copies the path; the menu also offers Show in Files.
struct RichPathChip: View {
    let path: String
    var glyph: String = "doc.text"

    @Environment(\.richActions) private var richActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            copyPath()
        } label: {
            PaseoCard(content:
                HStack(spacing: 8) {
                    Image(systemName: glyph)
                        .font(.glyph(.small))
                        .foregroundStyle(Palette.secondaryInk)
                    Text(path)
                        .font(.paseo(.codeSmall))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Image(systemName: "doc.on.doc")
                        .font(.glyph(.small))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .contentShape(.rect))
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .paseoCardMenu(copyTitle: "Copy path", copyText: path, filePath: path)
        .paseoCardAccessibility(kind: "File", title: path, isButton: true)
        .accessibilityHint("Copies the path")
    }

    private func copyPath() {
        if let richActions {
            richActions.copyText(path)
        } else {
            UIPasteboard.general.string = path
            Haptics.light()
        }
    }
}

// MARK: - The visualize fence (§1.6, §2)

/// A ` ```visualize ` block: a sandboxed WKWebView sized to its content, with a "View source"
/// toggle that swaps in the raw source with a copy button.
///
/// E3 §3.2: the height follows the reported content up to 70 % of the window height, animated
/// once per settled layout (the reporter debounces 100 ms and ignores sub-2-pt moves); past the
/// cap an "Open" button shows the page full screen.
///
/// The live web view exists only while the card is on screen and a slot is free (R9 §2). Off
/// screen the card draws its last snapshot, which is taken as it leaves; that keeps a long
/// transcript from holding one web process per card.
struct RichWebCard: View {
    let code: String

    @State private var showSource = false
    @State private var showFullScreen = false
    @State private var contentHeight: CGFloat = 240
    @State private var overflows = false
    @State private var isVisible = false
    @State private var holdsSlot = false
    @State private var snapshot: UIImage?
    @State private var width: CGFloat = 0
    /// The container's height, for the 70 % cap, known before the first frame.
    @Environment(\.richViewportHeight) private var viewportHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    /// A page that wants more than this gets the "Open" affordance instead.
    private var heightCap: CGFloat { viewportHeight * 0.7 }

    /// Built once per (content, scheme) instead of on every `body` pass.
    private var document: String {
        RichHTMLDocument.visualize(code: code, dark: colorScheme == .dark)
    }

    private var showsLive: Bool { isVisible && holdsSlot }

    var body: some View {
        PaseoCard(content:
            VStack(alignment: .leading, spacing: 10) {
                header
                if showSource {
                    source
                } else {
                    stage
                    if overflows {
                        openFullScreenButton
                    }
                }
            })
        .background { widthReader }
        .onAppear { setVisible(true) }
        .onDisappear { setVisible(false) }
        .onScrollVisibilityChange(threshold: 0.1) { visible in setVisible(visible) }
        .task(id: snapshotKey) { await captureSnapshotIfNeeded() }
        .sheet(isPresented: $showFullScreen) {
            SheetScaffold("Visualization", detents: .large) {
                SandboxedHTMLView(
                    html: document, heightFloor: 0, heightCeiling: .greatestFiniteMagnitude,
                    onHeightChange: { _ in }, fillsFrame: true)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Visualization")
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button {
                showSource.toggle()
            } label: {
                Text(showSource ? "Hide source" : "View source")
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .overlay(Capsule().strokeBorder(Palette.cardBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showSource ? "Hide source" : "View source")
        }
    }

    @ViewBuilder private var stage: some View {
        if showsLive {
            SandboxedHTMLView(
                html: document,
                heightFloor: 80,
                heightCeiling: heightCap,
                onHeightChange: { newHeight in
                    contentHeight = newHeight
                },
                onOverflowChange: { overflows = $0 }
            )
            .frame(height: contentHeight)
            .animation(Motion.disclosure.resolved(reduceMotion: reduceMotion), value: contentHeight)
        } else if let snapshot {
            Image(uiImage: snapshot)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: contentHeight)
        } else {
            Rectangle()
                .fill(Palette.codeSurface)
                .frame(height: contentHeight)
                .overlay { ProgressView().controlSize(.small).tint(Palette.secondaryInk) }
        }
    }

    private var openFullScreenButton: some View {
        Button {
            showFullScreen = true
        } label: {
            Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open visualization full screen")
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(code)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            HStack {
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = code
                    Haptics.light()
                } label: {
                    Label("Copy source", systemImage: "doc.on.doc")
                        .font(.paseo(.caption, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The card's inner width, for snapshots at the real size instead of a guess.
    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
        }
    }

    private var snapshotKey: String? {
        guard width > 1, !showsLive else { return nil }
        return RichSnapshotCache.key(html: document, width: width, dark: colorScheme == .dark)
    }

    /// Takes the slot when one is free; on the way out it snapshots first, so the card has
    /// something to show if it comes back — or stays off screen — without a live web view.
    @MainActor
    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        if visible {
            if !holdsSlot { holdsSlot = LiveWebViewBudget.shared.claim() }
        } else if holdsSlot {
            let html = document
            let renderWidth = max(width, 1)
            let dark = colorScheme == .dark
            let height = contentHeight
            holdsSlot = false
            LiveWebViewBudget.shared.release()
            Task { @MainActor in
                let key = RichSnapshotCache.key(html: html, width: renderWidth, dark: dark)
                if RichSnapshotCache.image(for: key) != nil { return }
                let rendered = await RichSnapshotQueue.shared.snapshot(
                    html: html, width: renderWidth, scale: displayScale)
                guard let rendered else { return }
                RichSnapshotCache.store(rendered, for: key)
                snapshot = rendered
                contentHeight = max(height, min(rendered.size.height, heightCap))
            }
        }
    }

    @MainActor
    private func captureSnapshotIfNeeded() async {
        guard let key = snapshotKey else { return }
        if let cached = RichSnapshotCache.image(for: key) {
            snapshot = cached
            return
        }
        let rendered = await RichSnapshotQueue.shared.snapshot(
            html: document, width: width, scale: displayScale)
        guard let rendered else { return }
        RichSnapshotCache.store(rendered, for: key)
        snapshot = rendered
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
