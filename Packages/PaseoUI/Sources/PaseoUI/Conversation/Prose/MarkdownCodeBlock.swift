#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One fenced code block: the language header with its copy / expand / preview actions, and the
/// horizontally scrolling code. It owns the expand sheet, so only a block that is actually
/// expanded presents anything and a document without code mounts no sheet host (W8).
///
/// Equatable on its value inputs, like `ClaudeMarkdownView`: the callbacks are stable objects'
/// methods and not part of equality, so a settled block is skipped when the document re-renders.
struct MarkdownCodeBlock: View, Equatable {
    nonisolated static func == (lhs: MarkdownCodeBlock, rhs: MarkdownCodeBlock) -> Bool {
        // Statements, not one `&&` chain: `theme` is main-actor isolated and an autoclosure is not.
        guard lhs.isStreaming == rhs.isStreaming else { return false }
        guard lhs.language == rhs.language, lhs.content == rhs.content else { return false }
        return lhs.theme == rhs.theme
    }

    let language: String?
    let content: String
    let theme: ClaudeMarkdownTheme
    /// True while the producing turn runs: the block waits for its fence to close before it asks
    /// the highlighter (R9 §1).
    let isStreaming: Bool
    let codeContent: ((String?, String) -> AttributedString)?
    let onAction: (MarkdownAction) -> Void

    @State private var expanded: ExpandedCode?

    /// Preview is explicit and never automatic (G5 §2 C8): closed html/svg fences offer it; a
    /// streaming fence is still arriving, so it doesn't.
    private var previewLanguage: String? {
        guard !isStreaming, let language,
            ["html", "svg"].contains(
                language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        else { return nil }
        return language
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "").font(.paseo(.code)).foregroundStyle(
                    theme.secondary)
                Spacer()
                Button(action: copyCode) {
                    MarkdownCodeIconLabel(title: "Copy code", systemImage: "square.on.square")
                }.accessibilityIdentifier("markdown.code.copy")
                Button(action: expandCode) {
                    MarkdownCodeIconLabel(
                        title: "Expand code", systemImage: "arrow.up.left.and.arrow.down.right")
                }.accessibilityIdentifier("markdown.code.expand")
                if let previewLanguage {
                    Button {
                        onAction(.previewCode(language: previewLanguage, content: content))
                    } label: {
                        MarkdownCodeIconLabel(title: "Preview", systemImage: "eye")
                    }.accessibilityIdentifier("markdown.code.preview")
                }
            }.foregroundStyle(theme.secondary).padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
            Rectangle().fill(theme.rule).frame(height: 0.5)
            ScrollView(.horizontal) {
                codeText.accessibilityIdentifier("markdown.code.content")
            }.scrollIndicators(.hidden).padding(Space.lg)
        }.background {
            RoundedRectangle(cornerRadius: Radius.group)
                .fill(theme.codeBackground)
                .stroke(theme.rule, lineWidth: 0.6)
        }.sheet(item: $expanded) { item in
            SheetScaffold(item.title, detents: .large) {
                ScrollView([.vertical, .horizontal]) {
                    codeText.accessibilityIdentifier("markdown.code.expandedContent")
                        .padding(Space.lg)
                }.defaultScrollAnchor(.topLeading, for: .alignment)
            }
        }
    }

    private var codeText: MarkdownCodeText {
        MarkdownCodeText(
            language: language, content: content, theme: theme, isStreaming: isStreaming,
            codeContent: codeContent)
    }

    private func copyCode() {
        onAction(.copyCode(content))
    }

    private func expandCode() {
        expanded = ExpandedCode(language: language, content: content)
        onAction(.expandCode(language: language, content: content))
    }
}
#endif
