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

    /// What the card's box is doing, as one value, so motion runs only when this changes.
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
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .mediaSlot(width: slotWidth, heightCap: heightCap)
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
                    .mediaSlot(width: slotWidth, heightCap: heightCap)
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

    /// One load per (path, pixel bucket, retry, workspace). The workspace is part of the key
    /// so a card drawn before the agent snapshot arrives (R1, V1.1) re-runs its load the
    /// moment `daemonWorkspaceID` becomes known.
    private var loadKey: String {
        let bucket = MediaSizing.pixelWidth(points: width, scale: displayScale)
        return "\(path)|\(bucket)|\(retryToken)|\(richActions?.daemonWorkspaceID ?? "-")"
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

    /// The kept box with the failure line, like the remote card: the reader watched the
    /// placeholder, so the box stays and only the inside is honest. Retry refetches.
    private func boxedFailure(_ failure: MediaFailure) -> some View {
        Rectangle()
            .fill(Palette.codeSurface)
            .aspectRatio(reservedAspect, contentMode: .fit)
            .mediaSlot(width: slotWidth, heightCap: heightCap)
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

    private func retry() {
        Haptics.light()
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
        // Offline fails closed: no fetch, the offline failure shows. Every other link fetches.
        if policy == .cacheOnly {
            if image == nil, failure == nil { failure = .offline }
            return
        }
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
#endif
