import Foundation
import Markdown

/// Value-only rendering model. Parsing uses Swift's official CommonMark/GFM AST.
public struct MarkdownDocumentModel: Equatable, Sendable {
    public let source: String
    public var blocks: [MarkdownBlock]
    public init(source: String) {
        self.source = source
        blocks = Document(parsing: source, options: [.disableSmartOpts]).children.map(MarkdownBlock.convert)
    }
    public init(source: String, blocks: [MarkdownBlock]) {
        self.source = source
        self.blocks = blocks
    }

    /// The document for `source`, reusing the last parse of the same text (P3).
    ///
    /// Parsing is pure and deterministic but not free: an 8 k-char answer costs ~0.4 ms to parse
    /// and turn into blocks. SwiftUI re-evaluates a view body far more often than its text
    /// changes — any store change, a keystroke somewhere else, a streamed token elsewhere — and
    /// every one of those used to re-parse every visible message. Main actor only, called from
    /// view bodies, like `RichContentCache`.
    @MainActor public static func cached(_ source: String) -> MarkdownDocumentModel {
        MarkdownDocumentCache.document(for: source)
    }
}

/// Small in-memory memo for the prose parse (P3), now an LRU under a byte budget
/// (P5-B): the previous table evicted wholesale at 64 entries, so scrolling back to an
/// earlier message re-parsed it. Keys share storage with the strings the views hold.
@MainActor
enum MarkdownDocumentCache {
    private static let table = ProseCache<String, MarkdownDocumentModel>(
        budget: 4 * 1024 * 1024,
        countLimit: 512,
        cost: { source, _ in source.utf8.count * 4 })

    static func document(for source: String) -> MarkdownDocumentModel {
        if let cached = table.value(for: source) { return cached }
        let document = MarkdownDocumentModel(source: source)
        table.setValue(document, for: source)
        return document
    }
}

/// A main-actor LRU memo for prose caches (markdown documents, rich detection,
/// linkified text). Entries are kept until the byte budget or the count limit is hit,
/// so a long answer stays warm while older pieces are evicted one at a time. The
/// recency list is a linked list so a hit is O(1); the array version scanned every
/// entry per hit, which is expensive when the keys are long streamed strings.
@MainActor
final class ProseCache<Key: Hashable, Value> {
    private final class Node {
        var key: Key
        var value: Value
        var cost: Int
        var previous: Node?
        var next: Node?
        init(key: Key, value: Value, cost: Int) {
            self.key = key
            self.value = value
            self.cost = cost
        }
    }

    private var nodes: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private var cost = 0
    private let budget: Int
    private let countLimit: Int
    private let costOf: (Key, Value) -> Int

    init(budget: Int, countLimit: Int, cost: @escaping (Key, Value) -> Int) {
        self.budget = max(1, budget)
        self.countLimit = max(1, countLimit)
        self.costOf = cost
    }

    func value(for key: Key) -> Value? {
        guard let node = nodes[key] else { return nil }
        moveToFront(node)
        return node.value
    }

    func setValue(_ value: Value, for key: Key) {
        let newCost = costOf(key, value)
        if let node = nodes[key] {
            cost += newCost - node.cost
            node.value = value
            node.cost = newCost
            moveToFront(node)
            return
        }
        let node = Node(key: key, value: value, cost: newCost)
        nodes[key] = node
        pushFront(node)
        cost += newCost
        evict()
    }

    private func moveToFront(_ node: Node) {
        guard head !== node else { return }
        detach(node)
        pushFront(node)
    }

    private func pushFront(_ node: Node) {
        node.previous = nil
        node.next = head
        head?.previous = node
        head = node
        if tail == nil { tail = node }
    }

    private func detach(_ node: Node) {
        node.previous?.next = node.next
        node.next?.previous = node.previous
        if head === node { head = node.next }
        if tail === node { tail = node.previous }
        node.previous = nil
        node.next = nil
    }

    private func evict() {
        while cost > budget || nodes.count > countLimit, let node = tail {
            detach(node)
            nodes.removeValue(forKey: node.key)
            cost -= node.cost
        }
    }
}
public enum MarkdownUnsupportedKind: String, Equatable, Sendable { case html, math, footnote, other }
public struct MarkdownImage: Equatable, Sendable {
    public var source: String
    public var title: String?
    public var alt: String
    public init(source: String, title: String? = nil, alt: String) {
        self.source = source
        self.title = title
        self.alt = alt
    }
}
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
public struct MarkdownListItem: Equatable, Sendable {
    public var checked: Bool?
    public var blocks: [MarkdownBlock]
    public init(checked: Bool? = nil, blocks: [MarkdownBlock]) {
        self.checked = checked
        self.blocks = blocks
    }
}
public enum MarkdownColumnAlignment: Sendable { case left, center, right }
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
        switch node {
        case let n as Paragraph: .paragraph(n.children.map(MarkdownInline.convert))
        case let n as Heading: .heading(level: n.level, content: n.children.map(MarkdownInline.convert))
        case let n as BlockQuote: .quote(n.children.map(convert))
        case is ThematicBreak: .rule
        case let n as CodeBlock: .code(language: n.language, content: n.code)
        case let n as OrderedList:
            .list(start: Int(n.startIndex), items: n.children.compactMap { ($0 as? ListItem).map(convertItem) })
        case let n as UnorderedList:
            .list(start: nil, items: n.children.compactMap { ($0 as? ListItem).map(convertItem) })
        case let n as Table:
            .table(
                header: n.head.children.map { $0.children.map(MarkdownInline.convert) },
                rows: n.body.children.map { $0.children.map { $0.children.map(MarkdownInline.convert) } },
                alignments: n.columnAlignments.map { $0 == .right ? .right : $0 == .center ? .center : .left })
        case let n as HTMLBlock: .unsupported(kind: .html, source: n.rawHTML)
        default: .unsupported(kind: .other, source: node.format())
        }
    }
    private static func convertItem(_ item: ListItem) -> MarkdownListItem {
        .init(checked: item.checkbox.map { $0 == .checked }, blocks: item.children.map(convert))
    }
}
extension MarkdownInline {
    static func convert(_ node: any Markup) -> MarkdownInline {
        switch node {
        case let n as Markdown.Text: .text(n.string)
        case is SoftBreak: .softBreak
        case is LineBreak: .hardBreak
        case let n as InlineCode: .code(n.code)
        case let n as Emphasis: .emphasis(n.children.map(convert))
        case let n as Strong: .strong(n.children.map(convert))
        case let n as Strikethrough: .strikethrough(n.children.map(convert))
        case let n as Markdown.Link: .link(destination: n.destination ?? "", children: n.children.map(convert))
        case let n as Markdown.Image:
            .image(
                .init(source: n.source ?? "", title: n.title, alt: n.children.map(convert).map(\.plainText).joined()))
        case let n as InlineHTML: .unsupported(kind: .html, source: n.rawHTML)
        default: .unsupported(kind: .other, source: node.format())
        }
    }
}

/// No action performs I/O. The host owns links, images, clipboard and unsupported extensions.
@nonexhaustive public enum MarkdownAction: Equatable, Sendable {
    case openLink(URL), image(MarkdownImage), copyCode(String)
    case expandCode(language: String?, content: String)
    /// "Preview" on a closed html/svg fence (G5 C8): never auto-rendered, always explicit.
    case previewCode(language: String?, content: String)
    case unsupported(kind: MarkdownUnsupportedKind, source: String)
    var presentationURL: URL? {
        var components = URLComponents()
        components.scheme = "claude-markdown"
        components.host = "presentation"
        switch self {
        case .image(let image):
            components.path = "/image"
            components.queryItems = [
                .init(name: "source", value: image.source), .init(name: "alt", value: image.alt),
                .init(name: "title", value: image.title)
            ]
        case .unsupported(let kind, let source):
            components.path = "/unsupported"
            components.queryItems = [.init(name: "kind", value: kind.rawValue), .init(name: "source", value: source)]
        default: return nil
        }
        return components.url
    }
    static func decodePresentationURL(_ url: URL) -> Self? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "claude-markdown",
            c.host == "presentation"
        else { return nil }
        func value(_ name: String) -> String? { c.queryItems?.first(where: { $0.name == name })?.value }
        guard let source = value("source") else { return nil }
        if c.path == "/image" { return .image(.init(source: source, title: value("title"), alt: value("alt") ?? "")) }
        if c.path == "/unsupported", let raw = value("kind"), let kind = MarkdownUnsupportedKind(rawValue: raw) {
            return .unsupported(kind: kind, source: source)
        }
        return nil
    }
}
