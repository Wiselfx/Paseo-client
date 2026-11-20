import Foundation
import Markdown
import PaseoStore

public indirect enum MarkdownInline: Equatable, Sendable {
    case text(String), softBreak, hardBreak, code(String)
    case emphasis([MarkdownInline]), strong([MarkdownInline]), strikethrough([MarkdownInline])
    case link(destination: String, children: [MarkdownInline]), image(MarkdownImage)
    case unsupported(kind: MarkdownUnsupportedKind, source: String)
    var containsInlineCode: Bool {
        switch self {
        case .code: true
        case .emphasis(let children), .strong(let children), .strikethrough(let children), .link(_, let children):
            children.contains(where: \.containsInlineCode)
        default: false
        }
    }
    public var plainText: String {
        switch self {
        case .text(let text), .code(let text), .unsupported(_, let text): text
        case .softBreak: " "
        case .hardBreak: "\n"
        case .emphasis(let children), .strong(let children), .strikethrough(let children), .link(_, let children):
            children.map(\.plainText).joined()
        case .image(let image): image.alt
        }
    }
}
extension MarkdownInline {
    static func convert(_ node: any Markup) -> MarkdownInline {
        convert(node, context: MarkdownInlineContext(home: nil))
    }

    /// The children a node contributes: one inline for most nodes, but plain text that
    /// carries bare URLs contributes `.text` + `.link` pieces, so callers flat-map.
    static func convertList(_ node: any Markup, context: MarkdownInlineContext) -> [MarkdownInline] {
        switch convert(node, context: context) {
        case .text(let text): return context.linkingBareURLs ? bareURLPieces(text) : [.text(text)]
        case let inline: return [inline]
        }
    }

    /// J2 §3: swift-markdown has no GFM autolink, so `https://swift.org/blog/` in a
    /// sentence stayed plain `.text`. Each URL becomes a `.link` whose only child is its
    /// own text, the shape an authored link has. Runs once per parse (the document
    /// cache), never per render, and never on text already inside a link.
    static func bareURLPieces(_ text: String) -> [MarkdownInline] {
        let ranges = BareURLScanner.ranges(in: text)
        guard !ranges.isEmpty else { return [.text(text)] }
        var pieces: [MarkdownInline] = []
        var cursor = text.startIndex
        for range in ranges {
            if cursor < range.lowerBound {
                pieces.append(.text(String(text[cursor..<range.lowerBound])))
            }
            let url = String(text[range])
            pieces.append(.link(destination: url, children: [.text(url)]))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { pieces.append(.text(String(text[cursor...]))) }
        return pieces
    }

    static func convert(_ node: any Markup, context: MarkdownInlineContext) -> MarkdownInline {
        switch node {
        case let n as Markdown.Text: .text(n.string)
        case is SoftBreak: .softBreak
        case is LineBreak: .hardBreak
        case let n as InlineCode: .code(n.code)
        case let n as Emphasis: .emphasis(n.children.map { convert($0, context: context) })
        case let n as Strong: .strong(n.children.map { convert($0, context: context) })
        case let n as Strikethrough: .strikethrough(n.children.map { convert($0, context: context) })
        case let n as Markdown.Link:
            .link(
                destination: context.destination(n.destination ?? ""),
                children: n.children.map { convert($0, context: context) })
        case let n as Markdown.Image:
            .image(
                .init(
                    source: context.imageSource(n.source ?? ""), title: n.title,
                    alt: n.children.map { convert($0, context: context) }.map(\.plainText).joined()))
        case let n as InlineHTML: .unsupported(kind: .html, source: n.rawHTML)
        default: .unsupported(kind: .other, source: node.format())
        }
    }
}
