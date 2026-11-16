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
    /// Starts the warm-up for the newest `limit` turns. Nothing is awaited; it never blocks the caller.
    @MainActor
    static func startForOpen(store: ConversationStore, limit: Int) {
        var texts: [String] = []
        for turn in store.turns.suffix(limit).reversed() {
            for segment in turn.segments.reversed() {
                guard case .prose(let row) = segment, case .assistantMessage(let message) = row.item
                else { continue }
                texts.append(message.text)
            }
        }
        guard !texts.isEmpty else { return }
        let home = store.agent?.cwd
        let dark = currentUserInterfaceIsDark()
        Task.detached(priority: .userInitiated) {
            await warm(texts: texts, home: home, dark: dark)
        }
    }

    @MainActor
    private static func currentUserInterfaceIsDark() -> Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let style = scene?.windows.first?.traitCollection.userInterfaceStyle ?? .unspecified
        return style == .dark
    }

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
