#if canImport(UIKit)
import Foundation
import PaseoStore
import UIKit

/// Builds, off the main actor, what the first render of a conversation's newest turns asks for on the
/// main actor (W1): the rich-piece split of each assistant message, the markdown document of each piece
/// and the syntax highlight of each fenced block. The caches (`RichPiecesCache`, `RichContentCache`,
/// `MarkdownDocumentCache`, `CodeHighlighter`) are thread-safe and keyed exactly as the views key them
/// (source text plus the agent's working directory), so a render that finds an entry reads the same
/// value it would have computed, and a render that does not find one computes it itself, as before.
/// Newest turns first: they are the ones on screen at the open.
enum ProseWarmup {
    /// The running open warm-up and the running prefetch warm-up. Each kind keeps its own handle, so
    /// a new prefetch batch cancels the previous prefetch (turns already scrolled past) without
    /// cancelling the open warm-up, and the other way round.
    @MainActor private static var openTask: Task<Void, Never>?
    @MainActor private static var prefetchTask: Task<Void, Never>?

    /// Starts the warm-up for the newest `limit` turns. Nothing is awaited; it never blocks the caller.
    @MainActor
    static func startForOpen(store: ConversationStore, limit: Int) {
        // A `let`: the Task below captures it, and a captured `var` is rejected in concurrent code.
        let texts = store.turns.suffix(limit).reversed().flatMap { proseTexts(of: $0) }
        guard !texts.isEmpty else { return }
        let home = store.agent?.cwd
        let dark = currentUserInterfaceIsDark()
        openTask?.cancel()
        openTask = Task(priority: .userInitiated) {
            await warm(texts: texts, home: home, dark: dark)
        }
    }

    /// Starts the warm-up for an explicit message list — a jump's target window, so its
    /// split, parse and highlight are warm before the rows build (W8). Same fire-and-forget
    /// shape as the open: short-lived and bounded by the caller's window. A newer call cancels the
    /// previous one, which `warm` observes through `Task.isCancelled`.
    @MainActor
    static func startForMessages(_ texts: [String], home: String?) {
        guard !texts.isEmpty else { return }
        let dark = currentUserInterfaceIsDark()
        prefetchTask?.cancel()
        prefetchTask = Task(priority: .userInitiated) {
            await warm(texts: texts, home: home, dark: dark)
        }
    }

    /// The assistant prose texts of one turn, newest first.
    static func proseTexts(of turn: Turn) -> [String] {
        var texts: [String] = []
        for segment in turn.segments.reversed() {
            guard case .prose(let row) = segment, case .assistantMessage(let message) = row.item
            else { continue }
            texts.append(message.text)
        }
        return texts
    }

    @MainActor
    private static func currentUserInterfaceIsDark() -> Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let style = scene?.windows.first?.traitCollection.userInterfaceStyle ?? .unspecified
        return style == .dark
    }

    /// `@concurrent`: the parse and highlight run off the main actor, which the `Task` started from
    /// the main actor would otherwise inherit.
    @concurrent
    private static func warm(texts: [String], home: String?, dark: Bool) async {
        var code: [(language: String?, content: String)] = []
        for text in texts {
            if Task.isCancelled { return }
            let pieces = PaseoPerf.measure("warm.pieces") { RichPiecesCache.pieces(text, home: home) }
            for piece in pieces {
                guard case .markdown(let chunk) = piece else { continue }
                let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let document = MarkdownDocumentCache.document(for: trimmed, home: home)
                collectCode(document.blocks, into: &code)
            }
        }
        let theme: ClaudeCodeSyntaxTheme = dark ? .dark : .light
        for block in code {
            if Task.isCancelled { return }
            _ = await CodeHighlighter.shared.highlight(block.content, language: block.language, theme: theme)
        }
    }

    private static func collectCode(
        _ blocks: [MarkdownBlock], into code: inout [(language: String?, content: String)]
    ) {
        for block in blocks {
            switch block {
            case .code(let language, let content): code.append((language, content))
            case .quote(let children): collectCode(children, into: &code)
            case .list(_, let items): for item in items { collectCode(item.blocks, into: &code) }
            default: break
            }
        }
    }
}
#endif
