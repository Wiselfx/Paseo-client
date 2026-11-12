#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - RichGalleryCard (G7 C2)

// NOTE: RemoteImagePipeline/G7: adjacent screenshots post as one grid card instead of a
// tall stack. Tiles crop (`scaledToFill`); the viewer always shows the full frame. One
// tap box covers the whole grid on metered links (§12); cache-only links show cached
// tiles or the reserved box, never a fetch.

/// A grid of 2+ adjacent images: 2 side by side (1:1), 3 with a large left tile (2:3),
/// 4 in a square, 5+ as 2×2 with a "+N" last tile. Fixed geometry from the count —
/// no measuring. Tapping a tile opens the shared viewer at that index, zooming from
/// that tile.
struct RichGalleryCard: View {
    let images: [RichImage]

    @Environment(\.richActions) private var richActions
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoom
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selection = 0
    @State private var showViewer = false
    @State private var tappedLoad = false
    @State private var shareImage: UIImage?
    /// The card's measured width, for decoding tiles at the size they draw at.
    @State private var width: CGFloat = 0
    /// Tiles that failed after an explicit fetch: a small glyph, and a tap retries.
    @State private var failedTiles: Set<String> = []

    private var tileIDs: [String] {
        images.map { image in
            switch image.source {
            case .remote(let url): "gallery-remote:\(url)"
            case .local(let path): "gallery-local:\(path)"
            }
        }
    }

    /// The §12 verdict for the grid, from the most constrained kind in it.
    private var policy: MediaFetchPolicy {
        let kind: MediaKind = images.contains {
            if case .local = $0.source { true } else { false }
        } ? .daemonImage : .remoteImage
        return mediaFetchPolicy(
            kind: kind, knownBytes: nil,
            condition: richActions?.linkCondition ?? .assumed)
    }

    private var capBytes: Int64? {
        guard !tappedLoad else { return nil }
        let kind: MediaKind = images.contains {
            if case .local = $0.source { true } else { false }
        } ? .daemonImage : .remoteImage
        return mediaDownloadCap(
            kind: kind, condition: richActions?.linkCondition ?? .assumed)
    }

    /// The tile slot in points: two columns whatever the geometry, so the decode
    /// matches the draw. Falls back to the old constant before layout lands.
    private var slotPoints: CGFloat {
        guard width > 1 else { return 180 }
        return max((width - Metrics.galleryTileSpacing) / 2, 1)
    }

    /// One load per count + tap state + width bucket: geometry never re-runs loads,
    /// and tiles skipped as cached never refetch on the re-run.
    private var loadKey: String {
        "\(images.count)|\(tappedLoad)|\(MediaSizing.pixelWidth(points: slotPoints, scale: displayScale))"
    }

    /// The card's inner width, measured on the frame it is actually drawn in.
    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
        }
    }

    /// The tile reads the decoded cache on the first pass: scrolling back draws
    /// instantly with no flash or jump, and `.task` only fetches what is missing.
    private func resolvedThumb(id: String, image: RichImage) -> UIImage? {
        if let thumb = thumbnails[id] { return thumb }
        guard let identity = cacheIdentity(for: image),
            let cached = MediaPipeline.cached(for: identity)
        else { return nil }
        return cached.image
    }

    private var viewerItems: [MediaViewerItem] {
        images.enumerated().map { index, image in
            let fileName: String = {
                switch image.source {
                case .remote(let url):
                    return MediaPipeline.target(for: url)?.lastPathComponent.nilIfEmpty ?? "image"
                case .local(let path):
                    return (path as NSString).lastPathComponent.nilIfEmpty ?? "image"
                }
            }()
            let fullSource: MediaSource? = {
                switch image.source {
                case .remote(let urlString):
                    return MediaPipeline.target(for: urlString).map(MediaSource.remote)
                case .local(let path):
                    guard let workspaceID = richActions?.daemonWorkspaceID else { return nil }
                    return .daemon(DaemonFileRef(
                        workspaceID: workspaceID, path: path, revision: nil))
                }
            }()
            return MediaViewerItem(
                id: tileIDs[index],
                thumbnail: thumbnails[tileIDs[index]],
                fullSource: fullSource,
                fileName: fileName,
                alt: image.alt.isEmpty ? fileName : image.alt,
                filePath: {
                    if case .local(let path) = image.source { path } else { nil }
                }())
        }
    }

    var body: some View {
        // Groups always hold 2+ images; anything else renders nothing.
        Group {
            if images.count >= 2 {
                PaseoMediaCard(media: grid)
                    .background { widthReader }
                    .overlay {
                        if showsTapBox {
                            tapOverlay
                        }
                    }
            }
        }
            .task(id: loadKey) { await loadAll() }
            .fullScreenCover(isPresented: $showViewer) {
                MediaViewerView(
                    items: viewerItems,
                    sourceID: tileIDs[clampedSelection],
                    namespace: zoom,
                    onClose: { showViewer = false },
                    selection: $selection)
            }
            .sheet(isPresented: Binding(get: { shareImage != nil }, set: { if !$0 { shareImage = nil } })) {
                if let shareImage {
                    ActivityView(items: [shareImage])
                }
            }
            // Contain, not combine: every tile stays its own VoiceOver button so the
            // reader can open image 2 of 5. The container carries the count.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(images.count) images")
    }

    private var clampedSelection: Int {
        min(max(selection, 0), max(images.count - 1, 0))
    }

    /// The reserved grid with a download action instead of bytes (§12).
    private var showsTapBox: Bool {
        guard !tappedLoad else { return false }
        return policy == .tapToDownload
    }

    private var tapOverlay: some View {
        Button {
            Haptics.light()
            tappedLoad = true
        } label: {
            Rectangle()
                .fill(Palette.codeSurface.opacity(0.92))
                .overlay {
                    VStack(spacing: Space.sm) {
                        Image(systemName: "arrow.down.circle")
                            .font(.glyph(.large, weight: .light))
                            .foregroundStyle(Palette.secondaryInk)
                        Text("Tap to download")
                            .font(.paseo(.caption, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text("\(images.count) images")
                            .font(.paseo(.codeCaption))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("Download \(images.count) images")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Downloads the gallery images")
    }

    // MARK: Layout (fixed geometry from the count)

    @ViewBuilder
    private var grid: some View {
        switch min(max(images.count, 2), 5) {
        case 2:
            HStack(spacing: Metrics.galleryTileSpacing) {
                tile(at: 0, aspect: 1)
                tile(at: 1, aspect: 1)
            }
        case 3:
            HStack(spacing: Metrics.galleryTileSpacing) {
                tile(at: 0, aspect: 2.0 / 3.0)
                VStack(spacing: Metrics.galleryTileSpacing) {
                    tile(at: 1, aspect: 1)
                    tile(at: 2, aspect: 1)
                }
            }
        default:
            let columns = [
                GridItem(.flexible(), spacing: Metrics.galleryTileSpacing),
                GridItem(.flexible(), spacing: Metrics.galleryTileSpacing),
            ]
            LazyVGrid(columns: columns, spacing: Metrics.galleryTileSpacing) {
                ForEach(0..<3, id: \.self) { index in
                    tile(at: index, aspect: 1)
                }
                ZStack {
                    tile(at: 3, aspect: 1)
                    if images.count > 4 {
                        Color.black.opacity(0.55)
                            .accessibilityHidden(true)
                        Text("+\(images.count - 4)")
                            .font(.paseo(.headline))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .accessibilityLabel("\(images.count - 4) more images")
                    }
                }
                .contentShape(.rect)
                .onTapGesture {
                    selection = 3
                    showViewer = true
                }
            }
        }
    }

    @ViewBuilder
    private func tile(at index: Int, aspect: CGFloat) -> some View {
        let id = tileIDs[index]
        let image = images[index]
        Button {
            if failedTiles.contains(id) {
                // A failed tile retries on tap: the reader's explicit fetch.
                failedTiles.remove(id)
                Task { @MainActor in
                    await loadTile(image: image, id: id, fetch: true)
                }
            } else {
                selection = index
                showViewer = true
            }
        } label: {
            ZStack {
                Rectangle().fill(Palette.codeSurface)
                if let uiImage = resolvedThumb(id: id, image: image) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else if failedTiles.contains(id) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.glyph(.regular, weight: .light))
                        .foregroundStyle(Palette.secondaryInk)
                        .accessibilityLabel("Couldn't load image")
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .clipped()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: id, in: zoom)
        .accessibilityHidden(showsTapBox)
        .paseoCardMenu(
            onShare: thumbnails[id] == nil ? nil : {
                shareImage = thumbnails[id]
            },
            copyTitle: "Copy link",
            copyText: copyText(for: image),
            saveImage: thumbnails[id],
            externalTitle: externalTitle(for: image),
            externalURL: externalURL(for: image),
            filePath: filePath(for: image))
        .accessibilityLabel("Image \(index + 1) of \(images.count), \(image.alt.isEmpty ? fileName(for: image) : image.alt)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the image full screen")
    }

    private func copyText(for image: RichImage) -> String? {
        if case .remote(let url) = image.source { url } else { nil }
    }

    private func externalTitle(for image: RichImage) -> String? {
        if case .remote = image.source { "Open link" } else { nil }
    }

    private func externalURL(for image: RichImage) -> URL? {
        if case .remote(let urlString) = image.source {
            return MediaPipeline.target(for: urlString).flatMap { url in
                guard url.scheme == "http" || url.scheme == "https" else { return nil }
                return url
            }
        }
        return nil
    }

    private func filePath(for image: RichImage) -> String? {
        if case .local(let path) = image.source { path } else { nil }
    }

    private func fileName(for image: RichImage) -> String {
        switch image.source {
        case .remote(let url):
            return MediaPipeline.target(for: url)?.lastPathComponent.nilIfEmpty ?? "image"
        case .local(let path):
            return (path as NSString).lastPathComponent.nilIfEmpty ?? "image"
        }
    }

    // MARK: Loading

    @MainActor
    private func loadAll() async {
        if !tappedLoad {
            switch policy {
            case .tapToDownload: return
            case .cacheOnly: break
            case .automatic: break
            }
        }
        // Offline (cacheOnly): no fetch. Cached tiles draw; the rest keep the box.
        // Sequential, not concurrent: one task per card, tiles arrive in document
        // order (progressive fidelity), and the shape matches the gated `.task`
        // call sites elsewhere (no unstructured cross-actor captures).
        let allowFetch = tappedLoad || policy == .automatic
        for (index, image) in images.enumerated() {
            let id = tileIDs[index]
            if let cached = resolvedThumb(id: id, image: image) {
                thumbnails[id] = cached
                continue
            }
            await loadTile(image: image, id: id, fetch: allowFetch)
            guard !Task.isCancelled else { return }
        }
    }

    @MainActor
    private func loadTile(image: RichImage, id: String, fetch: Bool) async {
        // Memory first: scrolling back draws instantly with no fade or jump.
        if let identity = cacheIdentity(for: image), let cached = MediaPipeline.cached(for: identity) {
            thumbnails[id] = cached.image
            MediaMetadataCache.remember(cached.aspectRatio, for: identity)
            return
        }
        guard fetch else { return }
        let source: MediaSource? = {
            switch image.source {
            case .remote(let urlString):
                return MediaPipeline.target(for: urlString).map(MediaSource.remote)
            case .local(let path):
                guard let workspaceID = richActions?.daemonWorkspaceID else { return nil }
                return .daemon(DaemonFileRef(workspaceID: workspaceID, path: path, revision: nil))
            }
        }()
        guard let source else { return }
        // Tiles crop: decode at the measured slot pixel width.
        let pixelWidth = MediaSizing.pixelWidth(points: slotPoints, scale: displayScale)
        for await event in await MediaPipeline.shared.events(
            source: source, pixelWidth: pixelWidth, capBytes: capBytes, ignoreFailureCache: false)
        {
            guard !Task.isCancelled else { return }
            if case .final(let outcome) = event {
                switch outcome {
                case .image(let payload):
                    thumbnails[id] = payload.image
                case .svg:
                    break
                case .failure:
                    failedTiles.insert(id)
                }
            }
        }
    }

    private func cacheIdentity(for image: RichImage) -> String? {
        switch image.source {
        case .remote(let urlString): MediaPipeline.cacheIdentity(for: urlString)
        case .local(let path):
            guard let workspaceID = richActions?.daemonWorkspaceID else { return nil }
            return MediaPipeline.liveKey(ref: DaemonFileRef(
                workspaceID: workspaceID, path: path, revision: nil))
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
