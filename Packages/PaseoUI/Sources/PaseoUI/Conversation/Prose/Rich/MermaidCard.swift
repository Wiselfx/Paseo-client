#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// A closed ` ```mermaid ` fence (C9): the diagram rendered once, offscreen, into a cached
/// image; the transcript shows only the image, never a live web view per diagram (§1.6.1).
/// A streaming fence never reaches this card — the detector keeps it a code block.
///
/// Box: the cached true ratio, else 4:3 until the render lands (one animated settle, then
/// never again for that source). Failures keep the box and show the source as code plus
/// the renderer's error. Tap opens the live vector diagram on the artifact page.
struct MermaidCard: View {
    let code: String

    @State private var image: UIImage?
    @State private var aspectRatio: CGFloat?
    @State private var svg: String?
    /// The renderer's message for a refused source. `.unavailable` is not a message: the card's
    /// title already says it (J1 §2 — never print the same sentence twice).
    @State private var errorMessage: String?
    @State private var showSource = false
    @State private var width: CGFloat = 0
    @Environment(\.artifactZoomNamespace) private var artifactZoom
    @Environment(\.richActions) private var richActions
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.richViewportHeight) private var viewportHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dark: Bool { colorScheme == .dark }

    /// Content identity: source plus scheme. The snapshot key adds the layout width;
    /// the shape (one settle per source, forever) does not.
    private var shapeKey: String { "mermaid:\(code.hashValue)" }

    /// The vector for the live view, keyed independently of layout width: one vector
    /// per source and scheme, whatever the card width.
    private var svgKey: String { shapeKey + "|" + (dark ? "d" : "l") }

    private var renderKey: String? {
        guard width > 1 else { return nil }
        return "\(shapeKey)|\(Int(width.rounded()))|\(dark ? "d" : "l")"
    }

    /// The ratio the box reserves: the diagram's own when known, else the 4:3 guess.
    private var reservedAspect: CGFloat { aspectRatio ?? 4.0 / 3.0 }

    private var heightCap: CGFloat { viewportHeight * 0.6 }

    /// The failure title, and the sentinel a `.unavailable` render stores in `errorMessage`: the
    /// renderer has no message of its own there, and printing this one twice is the J1 §2 bug.
    static let unavailable = "Couldn't render diagram"

    /// What the card's box is doing, as one value: the one animated settle is the
    /// placeholder → true ratio, once, and failures keep their box (§0).
    private struct Layout: Equatable {
        let aspectRatio: CGFloat
        let stage: Int
    }

    private var layout: Layout {
        var stage = 0
        if image != nil {
            stage = 2
        } else if errorMessage != nil {
            stage = 3
        } else if showSource {
            stage = 4
        }
        return Layout(aspectRatio: reservedAspect, stage: stage)
    }

    private var viewerSourceID: String { shapeKey }

    private var viewerDocument: ArtifactDocument {
        ArtifactDocument(
            kind: .mermaid(source: code, svg: svg, snapshot: image),
            shareImage: image)
    }

    var body: some View {
        PaseoCard(content:
            VStack(alignment: .leading, spacing: 10) {
                RichCardSourceHeader(title: "Diagram", showSource: $showSource, hideLabel: "View diagram")
                if showSource {
                    RichSourcePanel(code: code, role: .codeSmall)
                } else if let errorMessage, errorMessage == Self.unavailable {
                    unavailableStage
                } else if let errorMessage {
                    errorStage(message: errorMessage)
                } else {
                    diagram
                }
            })
        .background { widthReader }
        .animation(Motion.disclosure.resolved(reduceMotion: reduceMotion), value: layout)
        .task(id: renderKey) { await render() }
    }

    @ViewBuilder private var diagram: some View {
        if let image {
            Button(action: openViewer) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: heightCap)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .modifier(ArtifactZoomSource(id: viewerSourceID, namespace: artifactZoom))
            .accessibilityLabel("Diagram")
            .accessibilityHint("Opens the diagram full screen")
            .paseoCardMenu(
                copyTitle: "Copy source",
                copyText: code,
                viewSourceTitle: "View source",
                onViewSource: { showSource.toggle() })
        } else {
            Rectangle()
                .fill(Palette.codeSurface)
                .frame(maxWidth: .infinity)
                .frame(height: placeholderHeight)
                .overlay { ProgressView().controlSize(.small).tint(Palette.secondaryInk) }
                .accessibilityLabel("Loading diagram")
        }
    }

    /// The size the drawing will take, from its own ratio, so the card does not jump when
    /// the snapshot arrives. Before the first layout the width is unknown and the render
    /// has not started: the placeholder stays tiny for that one frame.
    private var placeholderHeight: CGFloat {
        guard width > 1 else { return min(Metrics.placeholderCompactHeight, heightCap) }
        return min(width / reservedAspect, heightCap)
    }

    /// The card's inner width, for rendering at the real size instead of a guess.
    private var widthReader: some View {
        // `onGeometryChange` on the clear background instead of a `GeometryReader` per card (W1): same
        // size, delivered at once and on change, written only when it differs.
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if width != newWidth { width = newWidth }
            }
    }

    /// A refused source shows the source as code, plus the renderer's message as a footer. An
    /// unavailable renderer has no message to add: the title is the whole failure (J1 §2).
    private func errorStage(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't render diagram")
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.failureInk)
            RichSourcePanel(code: code, role: .codeSmall)
            // V2.4 — the renderer's own message, already reduced to one line: never a bare
            // "A JavaScript exception occurred".
            Text(message)
                .font(.paseo(.codeCaption))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Diagram could not be rendered. \(message)")
    }

    private var unavailableStage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't render diagram")
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.failureInk)
            RichSourcePanel(code: code, role: .codeSmall)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Diagram could not be rendered.")
    }

    private func openViewer() {
        if let richActions {
            richActions.openArtifact(viewerDocument)
        }
    }

    /// One render per (content, width, scheme); hits draw from cache with no fade.
    @MainActor
    private func render() async {
        guard let key = renderKey else { return }
        if let cached = RichSnapshotCache.image(for: key) {
            image = cached
            svg = MermaidSVGCache.string(for: svgKey)
            return
        }
        if aspectRatio == nil,
            let aspect = MediaMetadataCache.aspectRatio(for: shapeKey)
        {
            aspectRatio = aspect
        }
        let outcome = await RichSnapshotQueue.shared.mermaid(
            source: code, dark: dark, slotWidth: width)
        guard !Task.isCancelled else { return }
        switch outcome {
        case .diagram(let rendered, let aspect, let renderedSVG):
            RichSnapshotCache.store(rendered, for: key)
            MermaidSVGCache.store(renderedSVG, for: svgKey)
            MediaMetadataCache.remember(aspect, for: shapeKey)
            image = rendered
            aspectRatio = aspect
            svg = renderedSVG
        case .error(let message):
            errorMessage = message
        case .unavailable:
            // The title alone: the source, then no second copy of the same sentence.
            errorMessage = Self.unavailable
        }
    }
}
#endif
