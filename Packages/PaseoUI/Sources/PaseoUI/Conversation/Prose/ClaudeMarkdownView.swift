#if canImport(UIKit)
    import PaseoStore
    import SwiftUI
    /// A markdown document. Each block is a named view (`MarkdownBlockView`); the code blocks and
    /// tables own their state (expand sheets, measured widths), so a change inside one never
    /// re-renders the whole document.
    public struct ClaudeMarkdownView: View, Equatable {
        /// R-2 (W1): equal inputs skip `body`. A streamed message is many of these in one stack, and
        /// every token re-ran every one of them (closures in the initialiser are never equal, so
        /// SwiftUI could not skip them): the settled pieces now draw once. The closures are not
        /// part of equality on purpose; they are stable objects' methods (`ChatActions`).
        nonisolated public static func == (lhs: ClaudeMarkdownView, rhs: ClaudeMarkdownView) -> Bool {
            // Statements, not one `&&` chain: `theme` is main-actor isolated and an autoclosure is not.
            guard lhs.isStreaming == rhs.isStreaming else { return false }
            guard lhs.theme == rhs.theme else { return false }
            guard lhs.document.source == rhs.document.source else { return false }
            return lhs.document.blocks == rhs.document.blocks
        }

        public let document: MarkdownDocumentModel
        public let theme: ClaudeMarkdownTheme
        private let codeContent: ((String?, String) -> AttributedString)?
        private let onAction: (MarkdownAction) -> Void
        /// True while the producing turn runs: code blocks wait for their fence to close before
        /// they ask the highlighter (R9 §1).
        private let isStreaming: Bool
        private let imageContent: ((MarkdownImage) -> AnyView)?
        private let unsupportedContent: ((MarkdownUnsupportedKind, String) -> AnyView)?
        public init(
            document: MarkdownDocumentModel, theme: ClaudeMarkdownTheme = .init(),
            imageContent: ((MarkdownImage) -> AnyView)? = nil,
            codeContent: ((String?, String) -> AttributedString)? = nil,
            unsupportedContent: ((MarkdownUnsupportedKind, String) -> AnyView)? = nil,
            isStreaming: Bool = false,
            onAction: @escaping (MarkdownAction) -> Void = { _ in }
        ) {
            self.document = document
            self.theme = theme
            self.imageContent = imageContent
            self.codeContent = codeContent
            self.unsupportedContent = unsupportedContent
            self.isStreaming = isStreaming
            self.onAction = onAction
        }
        public init(
            _ source: String, theme: ClaudeMarkdownTheme = .init(), isStreaming: Bool = false,
            onAction: @escaping (MarkdownAction) -> Void = { _ in }
        ) {
            self.init(
                document: .init(source: source), theme: theme, isStreaming: isStreaming,
                onAction: onAction)
        }
        public var body: some View {
            let _ = PaseoPerf.body("Markdown")
            MarkdownBlockList(
                blocks: document.blocks, path: "",
                context: MarkdownRenderContext(
                    theme: theme, isStreaming: isStreaming, onAction: onAction,
                    imageContent: imageContent, codeContent: codeContent,
                    unsupportedContent: unsupportedContent, tableVersions: document.tableVersions)
            )
            .foregroundStyle(theme.foreground)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    if let local = MarkdownAction.decodePresentationURL(url) {
                        onAction(local)
                    } else {
                        onAction(.openLink(url))
                    }
                    return .handled
                })
        }
    }
/// Content hashes for the stable `ForEach` identities (P5-B). `MarkdownBlock` is only
/// `Equatable` (its public contract), so the hash is written out rather than synthesized.
extension MarkdownInline {
    func hashStable(into hasher: inout Hasher) {
        switch self {
        case .text(let value): hasher.combine("text"); hasher.combine(value)
        case .softBreak: hasher.combine("softBreak")
        case .hardBreak: hasher.combine("hardBreak")
        case .code(let value): hasher.combine("code"); hasher.combine(value)
        case .emphasis(let children): hasher.combine("emphasis"); children.hashStable(into: &hasher)
        case .strong(let children): hasher.combine("strong"); children.hashStable(into: &hasher)
        case .strikethrough(let children): hasher.combine("strikethrough"); children.hashStable(into: &hasher)
        case .link(let destination, let children):
            hasher.combine("link"); hasher.combine(destination); children.hashStable(into: &hasher)
        case .image(let image):
            hasher.combine("image")
            hasher.combine(image.source)
            hasher.combine(image.title ?? "")
            hasher.combine(image.alt)
        case .unsupported(let kind, let source):
            hasher.combine("unsupported"); hasher.combine(kind.rawValue); hasher.combine(source)
        }
    }
}
extension Array where Element == MarkdownInline {
    func hashStable(into hasher: inout Hasher) {
        hasher.combine(count)
        for child in self { child.hashStable(into: &hasher) }
    }
}
extension MarkdownListItem {
    func hashStable(into hasher: inout Hasher) {
        hasher.combine(checked ?? false)
        hasher.combine(checked == nil)
        blocks.hashStable(into: &hasher)
    }
}
extension MarkdownBlock {
    func hashStable(into hasher: inout Hasher) {
        switch self {
        case .paragraph(let content): hasher.combine("paragraph"); content.hashStable(into: &hasher)
        case .heading(let level, let content):
            hasher.combine("heading"); hasher.combine(level); content.hashStable(into: &hasher)
        case .quote(let children): hasher.combine("quote"); children.hashStable(into: &hasher)
        case .rule: hasher.combine("rule")
        case .list(let start, let items):
            hasher.combine("list"); hasher.combine(start ?? -1); hasher.combine(items.count)
            for item in items { item.hashStable(into: &hasher) }
        case .code(let language, let content):
            hasher.combine("code"); hasher.combine(language ?? ""); hasher.combine(content)
        case .table(let header, let rows, let alignments):
            hasher.combine("table")
            header.hashStable(into: &hasher)
            hasher.combine(rows.count)
            for row in rows { row.hashStable(into: &hasher) }
            hasher.combine(alignments.count)
            for alignment in alignments {
                switch alignment {
                case .left: hasher.combine(0)
                case .center: hasher.combine(1)
                case .right: hasher.combine(2)
                }
            }
        case .unsupported(let kind, let source):
            hasher.combine("unsupported"); hasher.combine(kind.rawValue); hasher.combine(source)
        }
    }
}
extension Array where Element == MarkdownBlock {
    func hashStable(into hasher: inout Hasher) {
        hasher.combine(count)
        for block in self { block.hashStable(into: &hasher) }
    }
}
extension Array where Element == [MarkdownInline] {
    func hashStable(into hasher: inout Hasher) {
        hasher.combine(count)
        for row in self { row.hashStable(into: &hasher) }
    }
}
#endif
