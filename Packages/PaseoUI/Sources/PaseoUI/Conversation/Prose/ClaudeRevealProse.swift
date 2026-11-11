#if canImport(UIKit)
import SwiftUI

/// Chat-reveal (M7d §2, `chat-reveal` in DSH): newly arriving assistant prose fades in.
///
/// DSH drives this with the Custom Highlight API: every character fades over 120 ms from a
/// 0.2 floor (24 alpha steps) with a ~2.4 ms stagger. Here the same timing is expressed as a
/// left-to-right opacity sweep over a mask on the trailing Markdown piece — text already on
/// screen never re-animates (the sweep boundary only moves forward), history loads never
/// animate, and the sweep is one gradient.
///
/// A piece-level opacity fade is used for a rich block at the tail (blocks have no character
/// range the mask can lean on). Reduce Motion renders everything at full opacity, no sweep.
struct ClaudeRevealProse: View {
    let markdown: String
    let theme: ClaudeMarkdownTheme
    let onAction: (MarkdownAction) -> Void
    /// True while the producing turn is running — i.e. prose is actively arriving.
    let isStreaming: Bool
    /// Renders `![alt](url)` paragraphs: remote images through `MediaPipeline` (the shared
    /// cache, size probe, downsample and SVG path); workspace daemon paths through the same
    /// pipeline via `RichActions` in the environment.
    /// `nil` renders images as text.
    var imageContent: ((MarkdownImage) -> AnyView)? = nil

    static let minOpacity: Double = 0.2
    /// Width of the transition band between fully-shown and faded text, as a fraction of a piece.
    static let sweepRamp: CGFloat = 0.18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped on every streaming delta; drives the sweep animation task and the block fade.
    @State private var revealTick = 0
    /// Sweep boundary inside the tail piece: 1 renders the mask off; everything left of the
    /// boundary renders fully opaque, everything right of it ramps down to the floor.
    @State private var sweepBoundary: CGFloat = 1
    @State private var lastMarkdown = ""
    /// Identity of the trailing Markdown piece (UTF-16 start offset) and its length at the last
    /// delta — lets each delta sweep without re-parsing the previous text.
    @State private var tailStart = -1
    @State private var tailLength = 0

    private struct PieceRef {
        let id: Int
        let piece: RichPiece
        /// UTF-16 offset of the piece's first unit within the rendered piece stream.
        let start: Int
        /// UTF-16 length of the piece's source range.
        let length: Int
        /// The last non-empty Markdown piece — the one whose suffix fades in.
        var isTailMarkdown: Bool

        /// Stable identity (G1 §1.4): a block is its kind plus its start offset, so a newly
        /// detected block mid-stream never re-runs an older card's entrance; Markdown chunks
        /// keep their positional id.
        var stableIdentity: String {
            switch piece {
            case .markdown: "md:\(id)"
            case .block(let block, _): "block:\(block.cardKindKey):\(start)"
            }
        }
    }

    private func pieceRefs(_ source: String) -> [PieceRef] {
        let raw = richPieces(source)
        var refs: [PieceRef] = []
        var offset = 0
        for (index, piece) in raw.enumerated() {
            let length: Int
            switch piece {
            case .markdown(let chunk):
                length = chunk.utf16.count
            case .block(_, let blockLength):
                length = blockLength
            }
            refs.append(
                PieceRef(id: index, piece: piece, start: offset, length: length, isTailMarkdown: false))
            offset += length
        }
        if let last = raw.lastIndex(where: {
            if case .markdown(let chunk) = $0 {
                return !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return false
        }) {
            refs[last].isTailMarkdown = true
        }
        return refs
    }

    var body: some View {
        let refs = pieceRefs(markdown)
        VStack(alignment: .leading, spacing: theme.blockSpacing) {
            ForEach(refs, id: \.stableIdentity) { ref in
                switch ref.piece {
                case .markdown(let chunk):
                    let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        ClaudeMarkdownView(
                            document: .cached(trimmed), theme: theme,
                            imageContent: imageContent, isStreaming: isStreaming,
                            onAction: onAction)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .mask(sweepMask(active: ref.isTailMarkdown))
                    }
                case .block(let block, _):
                    ClaudeRichBlockView(block: block)
                        .phaseAnimator([Self.minOpacity, 1.0], trigger: revealTick) { content, phase in
                            content.opacity(
                                reduceMotion || !isStreaming || ref.id != refs.count - 1 ? 1 : phase)
                        } animation: { _ in
                            // R-4: the design system's fade, which Reduce Motion allows.
                            Motion.fade.animation
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            primeForHistory()
        }
        .onChange(of: markdown) { _, newValue in reveal(newValue, refs: refs) }
        .onChange(of: isStreaming) { _, streaming in
            if !streaming { sweepBoundary = 1 }
        }
        .task(id: revealTick) {
            guard revealTick > 0 else { return }
            withAnimation(Motion.fade.resolved(reduceMotion: reduceMotion)) { sweepBoundary = 1 }
        }
    }

    @ViewBuilder
    private func sweepMask(active: Bool) -> some View {
        if active, !reduceMotion, isStreaming, sweepBoundary < 1 {
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: sweepBoundary),
                    .init(
                        color: .white.opacity(Self.minOpacity),
                        location: min(1, sweepBoundary + Self.sweepRamp)),
                    .init(color: .white.opacity(Self.minOpacity), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color.white
        }
    }

    /// History must not animate: record the tail piece so the first delta only sweeps its suffix.
    private func primeForHistory(_ source: String? = nil) {
        let text = source ?? markdown
        lastMarkdown = text
        sweepBoundary = 1
        if let tail = pieceRefs(text).last(where: { $0.isTailMarkdown }) {
            tailStart = tail.start
            tailLength = tail.length
        } else {
            tailStart = -1
            tailLength = 0
        }
    }

    /// `refs` are the pieces of `source` already computed for this update's body —
    /// passing them avoids re-splitting the source on every delta.
    private func reveal(_ source: String, refs: [PieceRef]) {
        let priorMarkdown = lastMarkdown
        lastMarkdown = source
        guard isStreaming, !reduceMotion else {
            // History (or motion off): just track the tail, never animate.
            if let tail = refs.last(where: { $0.isTailMarkdown }) {
                tailStart = tail.start
                tailLength = tail.length
            }
            return
        }
        guard source.hasPrefix(priorMarkdown), source.utf16.count >= priorMarkdown.utf16.count
        else {
            // Rewritten rather than appended (rewind/refresh): no animation.
            primeForHistory(source)
            sweepBoundary = 1
            return
        }
        guard let tail = refs.last(where: { $0.isTailMarkdown }) else {
            if let last = refs.last, case .block = last.piece {
                revealTick += 1
            }
            return
        }
        let total = max(tail.length, 1)
        if tail.start == tailStart {
            // Same piece growing: only the newly arrived suffix starts faded.
            sweepBoundary = min(CGFloat(tailLength) / CGFloat(total), 1)
        } else {
            // A new trailing piece appeared (split/join): sweep the whole piece.
            sweepBoundary = 0
        }
        tailStart = tail.start
        tailLength = tail.length
        revealTick += 1
    }
}
#endif
