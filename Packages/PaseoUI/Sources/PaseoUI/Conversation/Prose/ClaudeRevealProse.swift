#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Assistant prose as it arrives. While the turn runs, the painted text is paced behind arrival
/// (`PaseoStore.TextReveal`, upstream `text-reveal.ts`): a burst releases over a few frames
/// instead of landing as one jump, and the text simply grows. Nothing on screen fades or sweeps:
/// the earlier character sweep masked the whole tail paragraph and re-faded the last card on every
/// delta, which flickered every line of it while the reply streamed. History never animates.
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

    @Environment(\.scenePhase) private var scenePhase
    /// The frame clock runs only for a live turn in the active scene: backgrounding stops
    /// the ticks (upstream's clock is rAF-driven, so a hidden tab stops free of charge).
    /// Keyed into `.task(id:)` below, so a phase flip restarts the task with a fresh key.
    private var pacingActive: Bool { isStreaming && scenePhase == .active }
    /// The agent's working directory (J2): `![a](~/shots/a.png)` and `[doc](docs/a.pdf)`
    /// resolve against it. Read here, in the leaf body, once per markdown change (R-1).
    @Environment(\.richActions) private var richActions
    /// The paced reveal (upstream `text-reveal.ts`, policy in `PaseoStore.TextReveal`): while
    /// the turn runs, arrival changes the target and the frame clock below releases the backlog
    /// proportionally — a burst catches up faster instead of jumping. The store keeps the full
    /// text; only this painted slice is paced, so copy, find and scroll geometry stay
    /// consistent with what is on screen. Nil when settled or complete (first sight paints
    /// whole, the turn's end paints everything). Written only while the backlog moves.
    @State private var paced: TextRevealState?

    /// What this update paints. While the turn runs, the slice paces behind arrival: deltas
    /// set the target and the frame clock below releases the backlog, at most once per 60 Hz
    /// frame, so a burst catches up faster instead of jumping (upstream `text-reveal.ts`).
    /// First sight paints whole; the turn's end paints everything. The store keeps the full text.
    private func paintedSource(markdown: String, isStreaming: Bool, paced: TextRevealState?) -> String {
        if isStreaming, let paced {
            return TextReveal.visibleText(paced, streaming: true)
        }
        if isStreaming {
            return TextReveal.trimmedForStreaming(markdown)
        }
        return markdown
    }

    private struct PieceRef {
        let id: Int
        let piece: RichPiece
        /// UTF-16 offset of the piece's first unit within the rendered piece stream.
        let start: Int
        /// UTF-16 length of the piece's source range.
        let length: Int
        /// The last Markdown piece: the one still arriving while the turn streams.
        var isTailMarkdown: Bool

        /// Stable identity (G1 §1.4): a block is its kind plus its start offset, so a newly
        /// detected block mid-stream never re-runs an older card's entrance; Markdown chunks
        /// keep their positional id.
        var stableIdentity: String {
            switch piece {
            case .markdown: "md:\(id)"
            case .block(let block, _): "block:\(block.cardKindKey):\(start)"
            case .file(let path, _): "file:\(path):\(start)"
            }
        }
    }

    /// The last split, so a body that runs again for the same painted text does not split the
    /// whole message again (W1).
    private final class PieceMemo {
        var source: String?
        var home: String?
        var refs: [PieceRef] = []
        /// The open piece's last parse while the turn streams (never stored in the shared cache).
        var tailText: String?
        var tailHome: String?
        var tailDocument: MarkdownDocumentModel?
    }
    @State private var memo = PieceMemo()

    private func pieceRefs(_ source: String) -> [PieceRef] {
        let home = richActions?.homeDirectory
        if memo.source == source, memo.home == home { return memo.refs }
        let refs = computePieceRefs(source, home: home)
        memo.source = source
        memo.home = home
        memo.refs = refs
        return refs
    }

    /// A settled piece is parsed once into the shared cache; the open piece of a running turn is
    /// parsed for this view only, so its partial copies never evict settled messages.
    private func document(_ text: String, open: Bool) -> MarkdownDocumentModel {
        let home = richActions?.homeDirectory
        guard open else { return .cached(text, home: home) }
        if memo.tailText == text, memo.tailHome == home, let document = memo.tailDocument {
            return document
        }
        let document = MarkdownDocumentModel.transient(text, home: home)
        memo.tailText = text
        memo.tailHome = home
        memo.tailDocument = document
        return document
    }

    private func computePieceRefs(_ source: String, home: String?) -> [PieceRef] {
        let raw = PaseoPerf.measure("rich.pieces") {
            RichPiecesCache.pieces(source, home: home, transient: isStreaming)
        }
        var refs: [PieceRef] = []
        var offset = 0
        for (index, piece) in raw.enumerated() {
            let length: Int
            switch piece {
            case .markdown(let chunk):
                length = chunk.utf16.count
            case .block(_, let blockLength), .file(_, let blockLength):
                length = blockLength
            }
            defer { offset += length }
            // Whitespace-only Markdown draws nothing: it is left out here, so every row of the
            // body is exactly one view.
            if case .markdown(let chunk) = piece,
                chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                continue
            }
            refs.append(
                PieceRef(id: index, piece: piece, start: offset, length: length, isTailMarkdown: false))
        }
        if let last = refs.lastIndex(where: {
            if case .markdown = $0.piece { true } else { false }
        }) {
            refs[last].isTailMarkdown = true
        }
        return refs
    }

    var body: some View {
        let _ = PaseoPerf.body("RevealProse")
        let _ = PaseoPerf.why(Self.self)
        let source = paintedSource(markdown: markdown, isStreaming: isStreaming, paced: paced)
        let refs = pieceRefs(source)
        VStack(alignment: .leading, spacing: theme.blockSpacing) {
            ForEach(refs, id: \.stableIdentity) { ref in
                switch ref.piece {
                case .markdown(let chunk):
                    ClaudeMarkdownView(
                        document: document(
                            chunk.trimmingCharacters(in: .whitespacesAndNewlines),
                            open: isStreaming && ref.isTailMarkdown),
                        theme: theme,
                        // Only the open piece can be still arriving. A settled piece sees
                        // `false` while the turn runs, so its code highlights as soon as its
                        // fence is closed and the turn ending changes one piece, not all of
                        // them (W1: `isStreaming` flipping made every piece unequal at once).
                        imageContent: imageContent, isStreaming: isStreaming && ref.isTailMarkdown,
                        onAction: onAction)
                        .equatable()
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .block(let block, _):
                    ClaudeRichBlockView(block: block)
                case .file(let path, _):
                    RichFileCard(path: path)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if isStreaming, paced == nil { paced = TextReveal.begin(markdown) }
        }
        .onChange(of: markdown) { _, newValue in
            guard isStreaming else { return }
            paced = paced.map { TextReveal.retarget($0, newValue) } ?? TextReveal.begin(newValue)
        }
        .onChange(of: isStreaming) { _, streaming in
            if !streaming { paced = nil }
        }
        // The reveal's frame clock (upstream `text-reveal.ts:nextTextRevealFrame`). Keyed on
        // the live-and-active flag — not per delta — so one task paces the whole turn; it
        // writes only while the backlog moves and idles without writing once settled (M05:
        // the one view that draws the paced text is the one invalidated). Cancelled on
        // disappear; backgrounding stops it, foregrounding resumes it into the backlog.
        .task(id: pacingActive) {
            guard pacingActive else { return }
            let clock = ContinuousClock()
            var last = clock.now
            var stampMs = 0.0
            var previousMs: Double?
            while !Task.isCancelled {
                // Half the upstream frame rate: each step re-lays-out the turn's cell, and the
                // backlog is released by elapsed time, so a step simply carries two frames' text.
                try? await Task.sleep(for: .seconds(2 * TextReveal.frameIntervalMs / 1000))
                guard !Task.isCancelled else { return }
                let now = clock.now
                let elapsed = now - last
                last = now
                let elapsedMs =
                    Double(elapsed.components.seconds) * 1000
                    + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
                guard elapsedMs > 0 else { continue }
                stampMs += elapsedMs
                guard
                    let frame = TextReveal.nextFrame(
                        previousFrameAtMs: previousMs, timestampMs: stampMs),
                    let current = paced
                else { continue }
                previousMs = frame.frameAtMs
                let next = TextReveal.advance(current, elapsedMs: frame.elapsedMs)
                if next.revealed != current.revealed { paced = next }
            }
        }
    }
}
#endif
