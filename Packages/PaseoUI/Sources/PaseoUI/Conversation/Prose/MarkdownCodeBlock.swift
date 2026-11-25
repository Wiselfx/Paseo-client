#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One fenced code block: the language header with its copy / expand / preview actions, and the
/// horizontally scrolling code. The inline code shows at most `inlineLineLimit` lines, and a row
/// under it opens the expand sheet for the rest, so a block lays out at most that many lines however
/// long it grows. The sheet draws every line. It owns the expand sheet, so only a block that is
/// actually expanded presents anything and a document without code mounts no sheet host (W8).
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

    /// Lines the inline code draws before its "Show N more lines" row. The expand sheet draws them all.
    static let inlineLineLimit = 24

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
        let hiddenLines = MarkdownCodeText.lineCount(of: content) - Self.inlineLineLimit
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
                codeText(maxLines: Self.inlineLineLimit)
                    .accessibilityIdentifier("markdown.code.content")
            }.scrollIndicators(.hidden).padding(Space.lg)
            if hiddenLines > 0 {
                Button(action: expandCode) {
                    Text("Show ^[\(hiddenLines) more line](inflect: true)")
                        .font(.paseo(.footnote, weight: .medium))
                        .foregroundStyle(theme.secondary)
                        .padding(.horizontal, Space.lg)
                        .frame(minHeight: Metrics.hitSize)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("markdown.code.more")
            }
        }.background {
            RoundedRectangle(cornerRadius: Radius.group)
                .fill(theme.codeBackground)
                .stroke(theme.rule, lineWidth: 0.6)
        }.sheet(item: $expanded) { item in
            SheetScaffold(item.title, detents: .large) {
                ScrollView([.vertical, .horizontal]) {
                    codeText(maxLines: nil)
                        .accessibilityIdentifier("markdown.code.expandedContent")
                        .padding(Space.lg)
                }.defaultScrollAnchor(.topLeading, for: .alignment)
            }
        }
    }

    /// The code's text, cut to `maxLines` lines when one is given. The inline block passes its limit;
    /// the expand sheet passes nil and draws all of it.
    private func codeText(maxLines: Int?) -> MarkdownCodeText {
        MarkdownCodeText(
            language: language, content: content, theme: theme, isStreaming: isStreaming,
            codeContent: codeContent, maxLines: maxLines)
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
