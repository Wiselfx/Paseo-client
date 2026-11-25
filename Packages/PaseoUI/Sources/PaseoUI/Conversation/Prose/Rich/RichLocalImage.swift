#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

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
    @State private var retryToken = 0
    @State private var downloadProgress: Double?
    @State private var width: CGFloat = 0
    @State private var showViewer = false
    @Namespace private var zoom
    @Environment(\.richViewportHeight) private var viewportHeight
    @Environment(\.richProseWidth) private var proseWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    private var heightCap: CGFloat { viewportHeight * 0.6 }

    /// The image slot's width: the prose column when the transcript published one, else this
    /// card's own measurement. Fixed, so the height is decided before the bytes arrive.
    private var slotWidth: CGFloat { proseWidth > 1 ? proseWidth : width }

    private var fileName: String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "image" : name
    }

    /// The zoom-transition source, stable per card.
    private var viewerSourceID: String { "local-image:\(path)" }

    /// One viewer page: the pixels on screen now, the full fetch behind them, with Show in
    /// Files for the daemon path (G3 §4.6).
    private var viewerItem: MediaViewerItem {
        MediaViewerItem(
            id: "local-image:\(path)",
            thumbnail: displayImage,
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

    /// The picture this card draws: the one it loaded, else the session's decoded copy of the same
    /// file. Read in `body` because the workspace id comes from the environment, so a card scrolled
    /// back into view draws its picture on the first frame instead of the placeholder.
    private var displayImage: UIImage? {
        image ?? ref.flatMap { MediaPipeline.cached(for: MediaPipeline.liveKey(ref: $0))?.image }
    }

    /// The ratio the box reserves: the image's own when this card knows it, else the session's
    /// record of the file's shape, else the 4:3 guess. Both known ratios exist before any pixel is
    /// drawn, so a revisit reserves its final box on the first frame.
    private var reservedAspect: CGFloat {
        aspectRatio
            ?? ref.flatMap { MediaMetadataCache.aspectRatio(for: MediaPipeline.liveKey(ref: $0)) }
            ?? 4.0 / 3.0
    }

    private var policy: MediaFetchPolicy {
        mediaFetchPolicy(
            kind: .daemonImage, knownBytes: nil,
            condition: richActions?.linkCondition ?? .assumed)
    }

    var body: some View {
        Group {
            if let displayImage {
                Button(action: openViewer) {
                    Image(uiImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .mediaSlot(width: slotWidth, heightCap: heightCap)
                        .background(Palette.codeSurface)
                        .clipShape(.rect(cornerRadius: Radius.md))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: viewerSourceID, in: zoom)
                .accessibilityLabel(alt.isEmpty ? fileName : alt)
                .accessibilityHint("Opens the image full screen")
                // The picture is the branch root, so the fade-in is its transition. Its arrival is
                // animated in `load()`; the box never is.
                .transition(.opacity)
            } else if failure != nil {
                if keepsFailureBox {
                    // The kept box with the failure line, like the remote card: the reader
                    // watched the placeholder, so the box stays and only the inside is honest.
                    // Retry refetches.
                    MediaFailureBox(aspect: reservedAspect, width: slotWidth, heightCap: heightCap) {
                        MediaFailureContent(detail: path, onRetry: retry)
                    }
                } else {
                    RichPathChip(path: path, glyph: "photo")
                }
            } else {
                MediaPlaceholder(
                    aspect: reservedAspect, width: slotWidth, heightCap: heightCap,
                    progress: downloadProgress, alt: alt)
            }
        }
        .background { widthReader }
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

    /// One load per (path, pixel bucket, retry, workspace, offline). The workspace is part of
    /// the key so a card drawn before the agent snapshot arrives (R1, V1.1) re-runs its load
    /// the moment `daemonWorkspaceID` becomes known; the offline flag so a card that stopped
    /// at "No connection" loads by itself when the connection returns.
    private var loadKey: String {
        let bucket = MediaSizing.pixelWidth(points: width, scale: displayScale)
        let workspace = richActions?.daemonWorkspaceID ?? "-"
        return "\(path)|\(bucket)|\(retryToken)|\(workspace)|\(policy == .cacheOnly)"
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

    private func openViewer() {
        showViewer = true
    }

    private func retry() {
        failure = nil
        keepsFailureBox = true
        downloadProgress = nil
        retryToken += 1
    }

    @MainActor
    private func load() async {
        guard let ref else {
            // No workspace id yet: a restored chat draws before the agent snapshot (V1.1).
            // `loadKey` carries the id, so this task re-runs when it lands. If it never does
            // (no conversation), answer honestly after the wait instead of spinning forever.
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled, image == nil, failure == nil {
                failure = .other
                keepsFailureBox = true
            }
            return
        }
        guard width > 1 else { return }
        // Offline fails closed: no fetch. An image already drawn this session still shows;
        // otherwise the offline failure shows in the kept box, with Try again.
        if policy == .cacheOnly {
            if image == nil, let cached = MediaPipeline.cached(for: MediaPipeline.liveKey(ref: ref)) {
                image = cached.image
                aspectRatio = cached.aspectRatio
                failure = nil
            }
            if image == nil, failure == nil {
                keepsFailureBox = true
                failure = .offline
            }
            return
        }
        // Back online: the placeholder replaces the offline failure while it loads.
        if failure == .offline { failure = nil }
        // The placeholder is on screen from here: a failure keeps its box.
        keepsFailureBox = true
        let pixelWidth = MediaSizing.pixelWidth(points: width, scale: displayScale)
        for await event in await MediaPipeline.shared.events(
            source: .daemon(ref), pixelWidth: pixelWidth,
            ignoreFailureCache: retryToken > 0)
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
                    // The box takes its final ratio at once; only the picture fades in over it.
                    aspectRatio = payload.aspectRatio
                    withAnimation(Motion.fade.resolved(reduceMotion: reduceMotion)) {
                        image = payload.image
                        failure = nil
                    }
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
        guard
            let rendered = await RichSVGImageRender.image(
                source: source, width: width, scale: displayScale, dark: colorScheme == .dark)
        else {
            // A render skipped because the card scrolled away is not a decoding failure.
            if !Task.isCancelled { failure = .decoding }
            return
        }
        guard !Task.isCancelled else { return }
        let size = rendered.size
        if size.height > 0 { aspectRatio = size.width / size.height }
        withAnimation(Motion.fade.resolved(reduceMotion: reduceMotion)) {
            image = rendered
            failure = nil
        }
    }
}
#endif
