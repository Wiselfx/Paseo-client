#if canImport(UIKit)
/// One fenced code block, highlighted **after** first paint (R9 §1).
///
/// The plain mono text is what mounts; the actor's tokens arrive a moment later and replace it with
/// the same font and metrics, so nothing moves. While the producing turn is still streaming the
/// block waits — the last fence of a running answer is not closed yet — and highlights once the
/// turn ends.
struct ClaudeHighlightedCode: View {
    let language: String?
    let content: String
    let theme: ClaudeMarkdownTheme
    /// The reveal's "still arriving" signal: true while the producing turn runs.
    let isStreaming: Bool

    @State private var highlighted: AttributedString?
    @Environment(\.colorScheme) private var colorScheme

    private var syntaxTheme: ClaudeCodeSyntaxTheme {
        colorScheme == .dark ? .dark : .light
    }

    /// Identity of the request: language, theme and the text's length. The actor caches on the
    /// source hash, so two revisions of different length are two entries, and a re-render of the
    /// same block asks for the same one.
    private var requestKey: String {
        "\(syntaxTheme.rawValue)/\(language ?? "")/\(content.utf16.count)"
    }

    var body: some View {
        Text(highlighted ?? CodeHighlightMirror.value(code: content, language: language, theme: syntaxTheme) ?? AttributedString(content))
            .font(theme.codeFont)
            .foregroundStyle(theme.foreground)
            .task(id: requestKey) {
                guard !isStreaming else { return }
                let result = await CodeHighlighter.shared.highlight(
                    content, language: language, theme: syntaxTheme)
                if highlighted != result { highlighted = result }
            }
            .onChange(of: isStreaming) { _, streaming in
                guard !streaming else { return }
                Task {
                    let result = await CodeHighlighter.shared.highlight(
                        content, language: language, theme: syntaxTheme)
                    if highlighted != result { highlighted = result }
                }
            }
    }
}
#endif
