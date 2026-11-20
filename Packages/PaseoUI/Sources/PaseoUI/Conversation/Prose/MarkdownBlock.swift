import Foundation
import Markdown
import PaseoStore

public indirect enum MarkdownBlock: Equatable, Sendable {
    case paragraph([MarkdownInline]), heading(level: Int, content: [MarkdownInline])
    case quote([MarkdownBlock]), rule
    case list(start: Int?, items: [MarkdownListItem])
    case code(language: String?, content: String)
    case table(header: [[MarkdownInline]], rows: [[[MarkdownInline]]], alignments: [MarkdownColumnAlignment])
    case unsupported(kind: MarkdownUnsupportedKind, source: String)
}
extension MarkdownBlock {
    static func convert(_ node: any Markup) -> MarkdownBlock {
        convert(node, context: MarkdownInlineContext(home: nil))
    }

    static func convert(_ node: any Markup, context: MarkdownInlineContext) -> MarkdownBlock {
        switch node {
        case let n as Paragraph: .paragraph(n.children.flatMap { MarkdownInline.convertList($0, context: context) })
        case let n as Heading:
            .heading(
                level: n.level,
                content: n.children.flatMap { MarkdownInline.convertList($0, context: context) })
        case let n as BlockQuote: .quote(n.children.map { convert($0, context: context) })
        case is ThematicBreak: .rule
        case let n as CodeBlock: .code(language: n.language, content: n.code)
        case let n as OrderedList:
            .list(
                start: Int(n.startIndex),
                items: n.children.compactMap {
                    ($0 as? ListItem).map { convertItem($0, context: context) }
                })
        case let n as UnorderedList:
            .list(
                start: nil,
                items: n.children.compactMap {
                    ($0 as? ListItem).map { convertItem($0, context: context) }
                })
        case let n as Table:
            .table(
                header: n.head.children.map {
                    $0.children.flatMap { MarkdownInline.convertList($0, context: context) }
                },
                rows: n.body.children.map {
                    $0.children.map {
                        $0.children.flatMap { MarkdownInline.convertList($0, context: context) }
                    }
                },
                alignments: n.columnAlignments.map { $0 == .right ? .right : $0 == .center ? .center : .left })
        case let n as HTMLBlock: .unsupported(kind: .html, source: n.rawHTML)
        default: .unsupported(kind: .other, source: node.format())
        }
    }
    private static func convertItem(_ item: ListItem, context: MarkdownInlineContext) -> MarkdownListItem {
        .init(
            checked: item.checkbox.map { $0 == .checked },
            blocks: item.children.map { convert($0, context: context) })
    }
}
