#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// A paragraph, heading or table cell. One SwiftUI `Text` for every paragraph (W1): inline code used to
/// be a `UIViewRepresentable` `UITextView` with its own TextKit 1 stack per paragraph (creation,
/// `sizeThatFits`, an attributed string rebuilt per pass; the dominant first-render cost of a long
/// chat). The pill behind inline code is drawn by `InlineCodeRenderer`, selection is
/// `.textSelection`, links go through the environment's `openURL`, exactly like the paragraphs
/// without code always did. The renderer is attached only when the paragraph has code.
struct MarkdownInlineText: View {
    let content: [MarkdownInline]
    let theme: ClaudeMarkdownTheme
    /// The run's base face; the theme's body face when nil.
    var font: Font? = nil
    var alignment: MarkdownColumnAlignment = .left

    private var frameAlignment: Alignment {
        alignment == .right ? .trailing : alignment == .center ? .center : .leading
    }

    private var textAlignment: TextAlignment {
        alignment == .right ? .trailing : alignment == .center ? .center : .leading
    }

    var body: some View {
        let face = font ?? theme.bodyFont
        if content.contains(where: \.containsInlineCode) {
            inlineText(content, font: face)
                .textRenderer(InlineCodeRenderer(background: theme.inlineCodeBackground))
                .lineSpacing(theme.lineSpacing).textSelection(.enabled)
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
        } else {
            inlineText(content, font: face)
                .lineSpacing(theme.lineSpacing).textSelection(.enabled)
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
        }
    }

    private func inlineText(
        _ children: [MarkdownInline], font: Font, bold: Bool = false, italic: Bool = false, strike: Bool = false,
        link: URL? = nil
    ) -> Text {
        children.reduce(Text("")) { result, child in
            let piece: Text
            switch child {
            case .strong(let nested):
                piece = inlineText(nested, font: font, bold: true, italic: italic, strike: strike, link: link)
            case .emphasis(let nested):
                piece = inlineText(nested, font: font, bold: bold, italic: true, strike: strike, link: link)
            case .strikethrough(let nested):
                piece = inlineText(nested, font: font, bold: bold, italic: italic, strike: true, link: link)
            case .link(let destination, let nested):
                piece = inlineText(
                    nested, font: font, bold: bold, italic: italic, strike: strike, link: URL(string: destination))
            default:
                var value = attributed([child], font: font, bold: bold, italic: italic, strike: strike)
                if let link {
                    value.link = link
                    value.foregroundColor = theme.link
                    value.underlineStyle = .single
                }
                // A link keeps the run's base face: underline and link colour only, as before
                // (its `.weight(.medium)` was a no-op on the static serif).
                if case .code = child {
                    // Inline code keeps the mono face: no strong, no emphasis (as before).
                    piece = Text(value).customAttribute(InlineCodeAttribute())
                } else {
                    piece = Text(value)
                }
            }
            return Text("\(result)\(piece)")
        }
    }

    private func attributed(
        _ children: [MarkdownInline], font: Font, bold: Bool = false, italic: Bool = false, strike: Bool = false
    ) -> AttributedString {
        var result = AttributedString()
        for child in children {
            var run = AttributedString()
            switch child {
            case .strong(let children):
                run = attributed(children, font: font, bold: true, italic: italic, strike: strike)
            case .emphasis(let children):
                run = attributed(children, font: font, bold: bold, italic: true, strike: strike)
            case .strikethrough(let children):
                run = attributed(children, font: font, bold: bold, italic: italic, strike: true)
            case .link(let destination, let children):
                run = attributed(children, font: font, bold: bold, italic: italic, strike: strike)
                run.link = URL(string: destination)
                run.foregroundColor = theme.link
                run.underlineStyle = .single
            default:
                let value: String
                switch child {
                case .image(let image): value = "▧ " + (image.alt.isEmpty ? "Image" : image.alt)
                default: value = child.plainText
                }
                run = AttributedString(value)
                var face = font
                if case .code = child {
                    face = theme.codeFont
                    run.foregroundColor = theme.inlineCodeForeground
                } else if bold || italic {
                    // A real face: the bundled serif has no bold or italic, so `.weight()`
                    // and `.italic()` would draw Regular (J1 §1).
                    face = theme.face(for: font, strong: bold, emphasis: italic)
                }
                run.font = face
                run.strikethroughStyle = strike ? .single : nil
                if case .image(let image) = child {
                    run.link = MarkdownAction.image(image).presentationURL
                    run.foregroundColor = theme.link
                }
                if case .unsupported(let kind, let source) = child {
                    run.link = MarkdownAction.unsupported(kind: kind, source: source).presentationURL
                }
            }
            result.append(run)
        }
        return result
    }
}
#endif
