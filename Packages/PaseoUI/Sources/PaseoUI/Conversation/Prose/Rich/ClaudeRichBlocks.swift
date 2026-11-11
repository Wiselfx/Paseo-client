#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// ClaudeUI card chrome for rich-content blocks: 14 pt radius, 0.5 pt hairline border,
/// the panel surface in both themes. `ClaudeCard` draws 10 pt, which predates the rich
/// card metrics; this mirrors it at the ticket's 12–16 pt range.
struct RichCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
            }
    }
}

/// Routes one detector block to its renderer, in document order (the caller iterates).
struct ClaudeRichBlockView: View {
    let block: RichContentBlock
    let localImageLoader: ((String) async -> UIImage?)?

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
            RichLocalImage(path: path, alt: alt, loader: localImageLoader)
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
    @State private var snapshot: UIImage?

    private var targetURL: URL? {
        if let lat = reference.latitude, let lng = reference.longitude {
            return URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)")
        }
        return URL(string: reference.url)
    }

    var body: some View {
        RichCard {
            Button {
                if let targetURL { openURL(targetURL) }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
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
                    .clipped()
                    .clipShape(.rect(cornerRadius: Radius.md))
                    HStack(spacing: 6) {
                        Image(systemName: "mappin")
                            .font(.glyph(.small, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                        Text(caption)
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open in Maps")
        }
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

    var body: some View {
        RichCard {
            Button {
                showSafari = true
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    if let metadata {
                        LinkPreviewView(metadata: metadata)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        placeholder
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(RichContentDetector.domain(for: url))")
        }
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

    private let playback = InlineYouTubePlayback.shared
    private var isPlaying: Bool { playback.activeID == reference.id }

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
            AsyncImage(
                url: URL(string: RichContentDetector.youTubeThumbnailURL(id: reference.id))
            ) { phase in
                switch phase {
                case .empty:
                    Rectangle().fill(Palette.codeSurface)
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle().fill(Palette.codeSurface)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.glyph(.xlarge, weight: .light))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                @unknown default:
                    Rectangle().fill(Palette.codeSurface)
                }
            }
            .clipped()

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

/// A remote image URL, loaded lazily when it scrolls into view. Tap opens the
/// full-screen viewer (ClaudeMediaViewer, reused).
///
/// E3 §3.5: full width, the image's own aspect ratio, capped at 60 % of the screen height; the
/// placeholder reserves a 4:3 box and the one change to the real ratio animates.
struct RichRemoteImage: View {
    let urlString: String
    let alt: String

    @State private var showViewer = false
    @State private var controlsVisible = true
    @State private var showShare = false
    @State private var loaded = false
    /// The window's height, for the 60 % cap (see `RichViewportHeight`).
    @State private var viewportHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var heightCap: CGFloat? { viewportHeight > 0 ? viewportHeight * 0.6 : nil }

    private var fileName: String {
        URL(string: urlString)?.lastPathComponent.nilIfEmpty ?? "image"
    }

    var body: some View {
        AsyncImage(url: URL(string: urlString)) { phase in
            switch phase {
            case .empty:
                placeholder
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: heightCap)
                    .background(Palette.codeSurface)
                    .clipShape(.rect(cornerRadius: Radius.md))
                    .contentShape(.rect)
                    .onTapGesture {
                        controlsVisible = true
                        showViewer = true
                    }
                    .onAppear { loaded = true }
            case .failure:
                brokenCard
            @unknown default:
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .background { RichViewportHeight { viewportHeight = $0 } }
        .animation(Motion.disclosure.resolved(reduceMotion: reduceMotion), value: loaded)
        .fullScreenCover(isPresented: $showViewer) {
            RichImageViewer(
                fileName: fileName,
                alt: alt.isEmpty ? fileName : alt,
                uiImage: nil,
                urlString: urlString,
                controlsVisible: $controlsVisible,
                onShare: {
                    showShare = true
                },
                onClose: { showViewer = false })
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: [URL(string: urlString) as Any])
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Palette.codeSurface)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: heightCap)
            .clipShape(.rect(cornerRadius: Radius.md))
            .overlay {
                ProgressView().controlSize(.small).tint(Palette.secondaryInk)
            }
    }

    private var brokenCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.glyph(.large, weight: .light))
                .foregroundStyle(Palette.secondaryInk)
            Text(urlString)
                .font(.paseo(.codeCaption))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
        }
    }
}

/// A bare local path to an image, read through the daemon (the files store the caller
/// threads in). Without a reachable store — or on any read failure — this falls back to
/// `RichPathChip`.
struct RichLocalImage: View {
    let path: String
    let alt: String
    let loader: ((String) async -> UIImage?)?

    @State private var image: UIImage?
    @State private var loaded = false
    @State private var showViewer = false
    @State private var controlsVisible = true
    @State private var showShare = false
    @State private var viewportHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var heightCap: CGFloat? { viewportHeight > 0 ? viewportHeight * 0.6 : nil }

    private var fileName: String {
        (path as NSString).lastPathComponent.nilIfEmpty ?? "image"
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
                    .onTapGesture {
                        controlsVisible = true
                        showViewer = true
                    }
            } else if loaded {
                RichPathChip(path: path, glyph: "photo")
            } else {
                Rectangle()
                    .fill(Palette.codeSurface)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: heightCap)
                    .clipShape(.rect(cornerRadius: Radius.md))
                    .overlay {
                        ProgressView().controlSize(.small).tint(Palette.secondaryInk)
                    }
            }
        }
        .background { RichViewportHeight { viewportHeight = $0 } }
        .animation(Motion.disclosure.resolved(reduceMotion: reduceMotion), value: image)
        .task {
            guard let loader else {
                loaded = true
                return
            }
            image = await loader(path)
            loaded = true
        }
        .fullScreenCover(isPresented: $showViewer) {
            RichImageViewer(
                fileName: fileName,
                alt: alt.isEmpty ? fileName : alt,
                uiImage: image,
                urlString: nil,
                controlsVisible: $controlsVisible,
                onShare: { showShare = true },
                onClose: { showViewer = false })
        }
        .sheet(isPresented: $showShare) {
            if let image {
                ActivityView(items: [image])
            }
        }
    }
}

/// Full-screen viewer, reusing ClaudeMediaViewer: black canvas, close button, the image
/// centered, share into UIActivityViewController.
struct RichImageViewer: View {
    let fileName: String
    let alt: String
    let uiImage: UIImage?
    let urlString: String?
    @Binding var controlsVisible: Bool
    let onShare: () -> Void
    let onClose: () -> Void

    var body: some View {
        let media = ClaudeMedia(
            id: "rich-\(fileName)", fileName: fileName, accessibilityDescription: alt,
            aspectRatio: uiImage.map { Double($0.size.width / max($0.size.height, 1)) } ?? 1)
        ClaudeMediaViewer(
            item: media,
            controlsVisible: controlsVisible,
            mediaContent: { _, _ in
                AnyView(viewerContent)
            },
            onAction: { action in
                switch action {
                case .close: onClose()
                case .toggleControls: controlsVisible.toggle()
                case .share: onShare()
                default: break
                }
            })
    }

    @ViewBuilder
    private var viewerContent: some View {
        if let uiImage {
            Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fit)
        } else if let urlString {
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                default:
                    ProgressView().tint(.white)
                }
            }
        } else {
            Color.clear
        }
    }
}

/// A mono path chip: for local image paths that can't be read, and for bare non-image
/// `file://` paths (§1.5). Tap copies the path.
struct RichPathChip: View {
    let path: String
    var glyph: String = "doc.text"

    var body: some View {
        Button {
            UIPasteboard.general.string = path
            Haptics.light()
        } label: {
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
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Path \(path). Copies the path.")
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
    /// The window's height, for the 70 % cap (see `RichViewportHeight`); nil before layout.
    @State private var viewportHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    /// A page that wants more than this gets the "Open" affordance instead.
    private var heightCap: CGFloat? { viewportHeight > 0 ? viewportHeight * 0.7 : nil }

    /// Built once per (content, scheme) instead of on every `body` pass.
    private var document: String {
        RichHTMLDocument.visualize(code: code, dark: colorScheme == .dark)
    }

    private var showsLive: Bool { isVisible && holdsSlot }

    var body: some View {
        RichCard {
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
            }
        }
        .background { widthReader }
        .background { RichViewportHeight { viewportHeight = $0 } }
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
        // No cap until the window is known: one layout pass, then the live card.
        if showsLive, let heightCap {
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
                contentHeight = max(
                    height, min(rendered.size.height, heightCap ?? rendered.size.height))
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
