#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit

/// ClaudeUI card chrome for rich-content blocks: 14 pt radius, 0.5 pt hairline border,
/// the panel surface in both themes. `ClaudeCard` draws 10 pt, which predates the rich
/// card metrics; this mirrors it at the ticket's 12–16 pt range.
struct RichCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(ClaudePalette.panel, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ClaudePalette.cardBorder, lineWidth: 0.5)
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
            RichWebCard(kind: .svg, code: source)
        case .visualize(let code, _):
            RichWebCard(kind: .visualize, code: code)
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

    private let typography = ClaudeTypography()

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
                            Rectangle().fill(ClaudePalette.codeSurface)
                                .overlay {
                                    Image(systemName: "map")
                                        .font(.system(size: 24, weight: .light))
                                        .foregroundStyle(ClaudePalette.secondaryInk)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipped()
                    .clipShape(.rect(cornerRadius: 12))
                    HStack(spacing: 6) {
                        Image(systemName: "mappin")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                        Text(caption)
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.secondaryInk)
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
        let options = MKMapSnapshotOptions()
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

    private let typography = ClaudeTypography()

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
        try await withCheckedThrowingContinuation { continuation in
            LPMetadataProvider().startFetchingMetadata(for: url) { metadata, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let metadata else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                continuation.resume(returning: metadata)
            }
        }
    }

    private var placeholderCard: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ClaudePalette.chip)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "link")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(RichContentDetector.domain(for: url))
                    .font(typography.sans(13, weight: .semibold))
                    .foregroundStyle(ClaudePalette.primaryInk)
                    .lineLimit(1)
                Text(RichContentDetector.displayURL(url))
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.secondaryInk)
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

/// Thumbnail card with a play glyph; tapping opens the watch URL. Full blocks take the
/// whole width at 4:3, in-sentence blocks are 16:9 capped at 320 pt — the spec's two
/// placements, both with the hqdefault poster.
struct YouTubeRichCard: View {
    let reference: YouTubeReference
    let full: Bool

    @Environment(\.openURL) private var openURL

    private let typography = ClaudeTypography()

    var body: some View {
        Button {
            if let target = URL(string: RichContentDetector.youTubeWatchURL(id: reference.id)) {
                openURL(target)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    // hqdefault letterboxes 16:9 inside 4:3; fill crop keeps it full-bleed.
                    AsyncImage(url: URL(string: RichContentDetector.youTubeThumbnailURL(id: reference.id))) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(ClaudePalette.codeSurface)
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            Rectangle().fill(ClaudePalette.codeSurface)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.system(size: 24, weight: .light))
                                        .foregroundStyle(ClaudePalette.secondaryInk)
                                }
                        @unknown default:
                            Rectangle().fill(ClaudePalette.codeSurface)
                        }
                    }
                    .frame(maxWidth: full ? .infinity : 320)
                    .aspectRatio(full ? 4.0 / 3.0 : 16.0 / 9.0, contentMode: .fit)
                    .clipped()

                    Circle()
                        .fill(.black.opacity(0.55))
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: 1)
                        }
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: full ? .infinity : 320, alignment: .leading)
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ClaudePalette.cardBorder, lineWidth: 0.5)
                }
                if full {
                    HStack(spacing: 6) {
                        Image(systemName: "play")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                        Text("youtube.com · \(reference.id)")
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: full ? .infinity : 320, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play YouTube video \(reference.id)")
    }
}

// MARK: - Images (§1.3–§1.5)

/// A remote image URL, loaded lazily when it scrolls into view. Tap opens the
/// full-screen viewer (ClaudeMediaViewer, reused).
struct RichRemoteImage: View {
    let urlString: String
    let alt: String

    @State private var showViewer = false
    @State private var controlsVisible = true
    @State private var showShare = false

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
                    .frame(maxWidth: .infinity)
                    .frame(height: 320, alignment: .center)
                    .background(ClaudePalette.codeSurface)
                    .clipShape(.rect(cornerRadius: 14))
                    .contentShape(.rect)
                    .onTapGesture {
                        controlsVisible = true
                        showViewer = true
                    }
            case .failure:
                brokenCard
            @unknown default:
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
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
            .fill(ClaudePalette.codeSurface)
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                ProgressView().controlSize(.small).tint(ClaudePalette.secondaryInk)
            }
    }

    private var brokenCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(ClaudePalette.secondaryInk)
            Text(urlString)
                .font(ClaudeTypography().mono(11))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClaudePalette.panel, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ClaudePalette.cardBorder, lineWidth: 0.5)
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

    private var fileName: String {
        (path as NSString).lastPathComponent.nilIfEmpty ?? "image"
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 320, alignment: .center)
                    .background(ClaudePalette.codeSurface)
                    .clipShape(.rect(cornerRadius: 14))
                    .contentShape(.rect)
                    .onTapGesture {
                        controlsVisible = true
                        showViewer = true
                    }
            } else if loaded {
                RichPathChip(path: path, glyph: "photo")
            } else {
                Rectangle()
                    .fill(ClaudePalette.codeSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay {
                        ProgressView().controlSize(.small).tint(ClaudePalette.secondaryInk)
                    }
            }
        }
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

    private let typography = ClaudeTypography()

    var body: some View {
        Button {
            UIPasteboard.general.string = path
            Haptics.selection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: glyph)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                Text(path)
                    .font(typography.mono(12))
                    .foregroundStyle(ClaudePalette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(ClaudePalette.secondaryInk)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(ClaudePalette.panel, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(ClaudePalette.cardBorder, lineWidth: 0.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Path \(path). Copies the path.")
    }
}

// MARK: - Raw SVG and the visualize fence (§1.6, §2)

enum RichWebKind {
    case visualize, svg
}

/// A web-backed block: a sandboxed WKWebView sized to its content (non-scrollable), with a
/// "View source" toggle that swaps in the raw source with a copy button.
struct RichWebCard: View {
    let kind: RichWebKind
    let code: String

    @State private var showSource = false
    @State private var contentHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private let typography = ClaudeTypography()

    init(kind: RichWebKind, code: String) {
        self.kind = kind
        self.code = code
        _contentHeight = State(initialValue: kind == .visualize ? 240 : 80)
    }

    private var document: String {
        let dark = colorScheme == .dark
        switch kind {
        case .visualize: return RichHTMLDocument.visualize(code: code, dark: dark)
        case .svg: return RichHTMLDocument.rawSVG(source: code, dark: dark)
        }
    }

    var body: some View {
        RichCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(kind == .visualize ? "Visualization" : "SVG")
                        .font(typography.sans(12, weight: .medium))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button {
                        showSource.toggle()
                    } label: {
                        Text(showSource ? "Hide source" : "View source")
                            .font(typography.mono(11))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .overlay(
                                Capsule().strokeBorder(ClaudePalette.cardBorder, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showSource ? "Hide source" : "View source")
                }
                if showSource {
                    ScrollView {
                        Text(code)
                            .font(typography.mono(11))
                            .foregroundStyle(ClaudePalette.primaryInk)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            UIPasteboard.general.string = code
                            Haptics.selection()
                        } label: {
                            Label("Copy source", systemImage: "doc.on.doc")
                                .font(typography.sans(12, weight: .medium))
                                .foregroundStyle(ClaudePalette.secondaryInk)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    SandboxedHTMLView(
                        html: document,
                        heightFloor: kind == .visualize ? 80 : 30,
                        heightCeiling: kind == .visualize ? 800 : 400
                    ) { newHeight in
                        contentHeight = newHeight
                    }
                    .frame(height: contentHeight)
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
