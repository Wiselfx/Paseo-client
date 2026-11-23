#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - RichGalleryCard (G7 C2)

// NOTE: RemoteImagePipeline/G7: adjacent screenshots post as one grid card instead of a
// tall stack. Tiles crop (`scaledToFill`); the viewer always shows the full frame.
// Images always load on live links (user directive); cache-only links show cached tiles, never a fetch.

/// A grid of 2+ adjacent images: 2 side by side (1:1), 3 with a large left tile (2:3),
/// 4 in a square, 5+ as 2×2 with a "+N" last tile. Fixed geometry from the count —
/// no measuring. Tapping a tile opens the shared viewer at that index, zooming from
/// that tile.
struct RichGalleryCard: View {
    let images: [RichImage]
    /// One stable id per image, mapped once at init: every tile, the viewer and each load step
    /// read it, so a computed property would remap the whole array on every read.
    private let tileIDs: [String]

    @Environment(\.richActions) private var richActions
    @Environment(\.richProseWidth) private var proseWidth
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var zoom
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selection = 0
    @State private var showViewer = false
    @State private var sharedImage: GallerySharedImage?
    /// The card's measured width, for decoding tiles at the size they draw at.
    @State private var width: CGFloat = 0
    /// Tiles that failed after an explicit fetch: a small glyph, and a tap retries.
    @State private var failedTiles: Set<String> = []
    /// Tiles with nothing cached while offline: no fetch was tried, and they say so.
    @State private var offlineTiles: Set<String> = []

    init(images: [RichImage]) {
        self.images = images
        tileIDs = images.map { image in
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

    /// The card's width: the prose column when the transcript published one, else the card's
    /// own measurement. Fixed, so the mosaic is decided before a tile decodes.
    private var cardWidth: CGFloat { proseWidth > 1 ? proseWidth : width }

    /// The tile slot in points: two columns whatever the geometry, so the decode
    /// matches the draw. Falls back to the old constant before layout lands.
    private var slotPoints: CGFloat {
        guard cardWidth > 1 else { return 180 }
        return max((cardWidth - Metrics.galleryTileSpacing) / 2, 1)
    }

    /// One load per count + width bucket + workspace + connectivity: geometry never re-runs
    /// loads, tiles skipped as cached never refetch on the re-run, a grid drawn before the
    /// agent snapshot names its workspace (V1.1) loads when the id lands, and a grid that
    /// stopped offline loads by itself when the connection returns.
    private var loadKey: String {
        "\(images.count)|\(MediaSizing.pixelWidth(points: slotPoints, scale: displayScale))"
            + "|\(richActions?.daemonWorkspaceID ?? "-")|\(policy == .automatic)"
    }

    /// The card's inner width, measured on the frame it is actually drawn in.
    private var widthReader: some View {
        // `onGeometryChange` on the clear background instead of a `GeometryReader` per card (W1): same
        // size, delivered at once and on change, written only when it differs.
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if width != newWidth { width = newWidth }
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
            let fileName = GalleryTile.fileName(for: image)
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
                    .mediaSlot(width: cardWidth, heightCap: .infinity)
                    .background { widthReader }
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
            .sheet(item: $sharedImage) { shared in
                ActivityView(items: [shared.image])
            }
            // Contain, not combine: every tile stays its own VoiceOver button so the
            // reader can open image 2 of 5. The container carries the count.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(images.count) images")
    }

    private var clampedSelection: Int {
        min(max(selection, 0), max(images.count - 1, 0))
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
                tile(at: 3, aspect: 1, moreCount: images.count > 4 ? images.count - 4 : nil)
            }
        }
    }

    private func tile(at index: Int, aspect: CGFloat, moreCount: Int? = nil) -> some View {
        let id = tileIDs[index]
        let image = images[index]
        return GalleryTile(
            image: image,
            index: index,
            count: images.count,
            aspect: aspect,
            displayed: resolvedThumb(id: id, image: image),
            saved: thumbnails[id],
            failed: failedTiles.contains(id),
            offline: offlineTiles.contains(id),
            moreCount: moreCount,
            sourceID: id,
            namespace: zoom,
            onOpen: { open(at: index) },
            onRetry: { retry(image: image, id: id) },
            onShare: { sharedImage = GallerySharedImage(image: $0) })
    }

    private func open(at index: Int) {
        selection = index
        showViewer = true
    }

    /// A failed tile retries on tap: the reader's explicit fetch.
    private func retry(image: RichImage, id: String) {
        failedTiles.remove(id)
        offlineTiles.remove(id)
        Task { @MainActor in
            await loadTile(image: image, id: id, fetch: true)
        }
    }

    // MARK: Loading

    /// How many tiles load at once: enough that a short grid does not wait on each download
    /// in turn, few enough not to flood the connection.
    private static let loadConcurrency = 3

    @MainActor
    private func loadAll() async {
        // Tiles already in the decoded cache draw at once; the rest are the ones to fetch.
        var pending: [Int] = []
        for (index, image) in images.enumerated() {
            let id = tileIDs[index]
            if let cached = resolvedThumb(id: id, image: image) {
                thumbnails[id] = cached
                offlineTiles.remove(id)
                continue
            }
            pending.append(index)
        }
        // Offline (cacheOnly): no fetch. Cached tiles draw; the rest say there is no connection.
        guard policy == .automatic else {
            offlineTiles = Set(pending.map { tileIDs[$0] })
            return
        }
        offlineTiles = []
        // Bounded concurrency: `loadConcurrency` lanes, each loading every nth pending tile in
        // turn. Tiles are keyed by id, so each lands in its own slot whatever order the
        // downloads finish in. The lanes are main-actor tasks (a task group capturing the view
        // trips the region checker); cancelling this load cancels them.
        var lanes: [Task<Void, Never>] = []
        for lane in 0..<Self.loadConcurrency {
            let indices = Array(stride(from: lane, to: pending.count, by: Self.loadConcurrency))
                .map { pending[$0] }
            guard !indices.isEmpty else { break }
            lanes.append(
                Task { @MainActor in
                    for index in indices {
                        guard !Task.isCancelled else { return }
                        await loadTile(at: index)
                    }
                })
        }
        let running = lanes
        await withTaskCancellationHandler {
            for lane in running { await lane.value }
        } onCancel: {
            for lane in running { lane.cancel() }
        }
    }

    @MainActor
    private func loadTile(at index: Int) async {
        await loadTile(image: images[index], id: tileIDs[index], fetch: true)
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
            source: source, pixelWidth: pixelWidth, ignoreFailureCache: false)
        {
            guard !Task.isCancelled else { return }
            if case .final(let outcome) = event {
                switch outcome {
                case .image(let payload):
                    thumbnails[id] = payload.image
                case .svg(let source, _):
                    await renderSVG(source, id: id)
                case .failure:
                    failedTiles.insert(id)
                }
            }
        }
    }

    /// SVG tiles draw through the shared offscreen renderer (cached by content and width), so
    /// they get a picture or the failure glyph like every other tile.
    @MainActor
    private func renderSVG(_ source: String, id: String) async {
        guard
            let rendered = await RichSVGImageRender.image(
                source: source, width: slotPoints, scale: displayScale,
                dark: colorScheme == .dark)
        else {
            // A render skipped because the card scrolled away is not a failure.
            if !Task.isCancelled { failedTiles.insert(id) }
            return
        }
        guard !Task.isCancelled else { return }
        thumbnails[id] = rendered
    }

    private func cacheIdentity(for image: RichImage) -> String? {
        switch image.source {
        case .remote(let urlString): return MediaPipeline.cacheIdentity(for: urlString)
        case .local(let path):
            guard let workspaceID = richActions?.daemonWorkspaceID else { return nil }
            return MediaPipeline.liveKey(ref: DaemonFileRef(
                workspaceID: workspaceID, path: path, revision: nil))
        }
    }
}
#endif
