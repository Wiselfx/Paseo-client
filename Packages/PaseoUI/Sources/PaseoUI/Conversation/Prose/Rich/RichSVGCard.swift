#if canImport(UIKit)
import OSLog
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// A raw `<svg>` block (E3 §3.1): a snapshot of the drawing at the transcript width, its
/// intrinsic aspect ratio reserved before the render lands, capped at 60 % of the screen
/// height, and a full-screen pinch-zoom viewer on tap. A drawing taller than the cap also
/// offers "Open" for the artifact page, where it is whole and vector. No inner scrolling,
/// no live web view per card.
///
/// The snapshot is keyed by (content, width, scheme); the latest one is also remembered per
/// content, so a card recreated by the transcript draws the drawing on its first frame.
struct RichSVGCard: View {
    let code: String
    /// Source identity and the drawing's own ratio, computed once per view value: both are
    /// read from `body` (cache key, reserved height, viewer identity) and neither may scan
    /// the source per layout pass (R-1).
    private let contentKey: String
    private let intrinsicAspectRatio: CGFloat?

    init(code: String) {
        self.code = code
        self.contentKey = "svg:\(code.hashValue)"
        self.intrinsicAspectRatio = RichSVGIntrinsic.aspectRatio(of: code)
    }

    @State private var image: UIImage?
    @State private var showSource = false
    @State private var showViewer = false
    @State private var width: CGFloat = 0
    @Namespace private var zoom
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.richActions) private var richActions

    private var dark: Bool { colorScheme == .dark }

    /// The drawing at the current width, or the latest one from another width: a revisit's
    /// first frame draws the cached drawing instead of a placeholder.
    private var resolvedImage: UIImage? {
        image ?? RichSnapshotCache.lastImage(for: contentKey, dark: dark)
    }

    /// The container's height, for the 60 % cap, known before the first frame (`RichViewport`).
    @Environment(\.richViewportHeight) private var viewportHeight

    /// A tall drawing shrinks to fit instead of pushing the turn away.
    private var heightCap: CGFloat { viewportHeight * 0.6 }

    /// True when the drawing at this width is clipped by the cap: the card offers the page.
    private var isTall: Bool {
        guard let ratio = intrinsicAspectRatio, ratio > 0, width > 1 else { return false }
        return width / ratio > heightCap + 0.5
    }

    var body: some View {
        PaseoCard(content:
            VStack(alignment: .leading, spacing: 10) {
                RichCardSourceHeader(title: "SVG", showSource: $showSource)
                if showSource {
                    RichSourcePanel(code: code)
                } else {
                    drawing
                    if isTall {
                        RichOpenButton(
                            accessibilityText: "Open SVG full screen", action: openArtifactPage)
                    }
                }
            })
        .background { widthReader }
        .task(id: renderKey) { await render() }
        .onChange(of: colorScheme) { _, _ in
            // The snapshot bakes the scheme in; the cache lookup for the new scheme draws
            // on the next pass and the width-keyed render replaces it.
            image = nil
        }
        .fullScreenCover(isPresented: $showViewer) {
            if let drawing = resolvedImage {
                MediaViewerView(
                    items: [
                        MediaViewerItem(
                            id: contentKey,
                            thumbnail: drawing,
                            fullSource: nil,
                            fileName: "drawing.svg",
                            alt: "SVG drawing",
                            filePath: nil)
                    ],
                    sourceID: contentKey,
                    namespace: zoom,
                    onClose: { showViewer = false },
                    selection: .constant(0))
            }
        }
    }

    @ViewBuilder private var drawing: some View {
        if let drawing = resolvedImage {
            Button(action: openViewer) {
                Image(uiImage: drawing)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: heightCap)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: contentKey, in: zoom)
            .accessibilityLabel("SVG drawing")
            .accessibilityHint("Opens the drawing full screen")
        } else {
            Rectangle()
                .fill(Palette.codeSurface)
                .frame(maxWidth: .infinity)
                .frame(height: placeholderHeight)
                .overlay { ProgressView().controlSize(.small).tint(Palette.secondaryInk) }
        }
    }

    /// The size the drawing will take, from its own ratio, so the card does not jump when the
    /// snapshot arrives. Falls back to a 120 pt strip for a drawing with no size hints.
    private var placeholderHeight: CGFloat {
        guard let ratio = intrinsicAspectRatio, ratio > 0 else { return min(120, heightCap) }
        // Before layout the width is unknown; assume a phone-width card.
        let assumedWidth = width > 1 ? width : 350
        return min(assumedWidth / ratio, heightCap)
    }

    /// The card's inner width, for rendering the drawing at its real size instead of a guess.
    private var widthReader: some View {
        // `onGeometryChange` on the clear background instead of a `GeometryReader` per card (W1): same
        // size, delivered at once and on change, written only when it differs.
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if width != newWidth { width = newWidth }
            }
    }

    /// Nil until the width is known: a render at a guessed width would only be thrown away.
    private var renderKey: String? {
        guard width > 1 else { return nil }
        return RichSnapshotCache.key(content: contentKey, width: width, dark: dark)
    }

    @MainActor
    private func render() async {
        guard let key = renderKey else { return }
        if let cached = RichSnapshotCache.image(for: key) {
            image = cached
            return
        }
        let html = RichHTMLDocument.rawSVG(source: code, dark: dark)
        let rendered = await RichSnapshotQueue.shared.snapshot(
            html: html, width: width, scale: displayScale)
        guard !Task.isCancelled, let rendered else { return }
        RichSnapshotCache.store(rendered, for: key, content: contentKey, dark: dark)
        image = rendered
    }

    private func openViewer() {
        showViewer = true
    }

    /// The tall drawing's home: the artifact page shows the whole vector, at any width.
    private func openArtifactPage() {
        if let richActions {
            richActions.openArtifact(
                ArtifactDocument(kind: .svg(source: code), shareImage: resolvedImage))
        }
    }
}
#endif
