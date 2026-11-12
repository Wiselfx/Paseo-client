import Foundation
import Markdown
import PaseoStore

/// Value-only rendering model. Parsing uses Swift's official CommonMark/GFM AST.
public struct MarkdownDocumentModel: Equatable, Sendable {
    public let source: String
    public var blocks: [MarkdownBlock]
    /// Per-table content versions, by block index (Phase C §9.1): a hash of the
    /// table's cell text, computed once per parse and memoised with the cached
    /// document. The layout remeasures when it changes (streamed text grows with
    /// the cell count unchanged); settled tables never change it, so steady state
    /// is still zero measurement.
    public var tableVersions: [Int: Int]
    public init(source: String) {
        self.source = source
        let parsed = Document(parsing: source, options: [.disableSmartOpts]).children.map(
            MarkdownBlock.convert)
        blocks = parsed
        tableVersions = Self.tableVersions(for: parsed)
    }

    /// J2: authored destinations the app's environment must handle itself — a local file
    /// (`paseo-file:` links, and a link whose scheme was missing) and a bare URL wrapped
    /// into a link. Nil is the common case and keeps rendering exactly as before.
    public init(source: String, home: String?) {
        self.source = source
        let parsed = Document(parsing: source, options: [.disableSmartOpts]).children.map {
            MarkdownBlock.convert($0, context: MarkdownInlineContext(home: home))
        }
        blocks = parsed
        tableVersions = Self.tableVersions(for: parsed)
    }
    public init(source: String, blocks: [MarkdownBlock]) {
        self.source = source
        self.blocks = blocks
        tableVersions = Self.tableVersions(for: blocks)
    }

    private static func tableVersions(for blocks: [MarkdownBlock]) -> [Int: Int] {
        var versions: [Int: Int] = [:]
        for (index, block) in blocks.enumerated() {
            guard case .table(let header, let rows, _) = block else { continue }
            var hasher = Hasher()
            hasher.combine(rows.count)
            for cell in header { hasher.combine(cell.map(\.plainText).joined(separator: "\u{1F}")) }
            for row in rows {
                for cell in row {
                    hasher.combine(cell.map(\.plainText).joined(separator: "\u{1F}"))
                }
            }
            versions[index] = hasher.finalize()
        }
        return versions
    }

    /// The document for `source`, reusing the last parse of the same text (P3).
    ///
    /// Parsing is pure and deterministic but not free: an 8 k-char answer costs ~0.4 ms to parse
    /// and turn into blocks. SwiftUI re-evaluates a view body far more often than its text
    /// changes — any store change, a keystroke somewhere else, a streamed token elsewhere — and
    /// every one of those used to re-parse every visible message. Main actor only, called from
    /// view bodies, like `RichContentCache`.
    ///
    /// `home` (the agent's working directory) rewrites authored links to local files into
    /// `paseo-file:` URLs and wraps bare URLs found in text (J2); nil is the plain parse. It is
    /// part of the cache key, so one text parsed for two workspaces is two entries.
    @MainActor public static func cached(_ source: String, home: String? = nil) -> MarkdownDocumentModel {
        MarkdownDocumentCache.document(for: source, home: home)
    }
}

/// Small in-memory memo for the prose parse (P3), now an LRU under a byte budget
/// (P5-B): the previous table evicted wholesale at 64 entries, so scrolling back to an
/// earlier message re-parsed it. Keys share storage with the strings the views hold.
@MainActor
enum MarkdownDocumentCache {
    private struct Key: Hashable {
        let source: String
        let home: String?
    }

    private static let table = ProseCache<Key, MarkdownDocumentModel>(
        budget: 4 * 1024 * 1024,
        countLimit: 512,
        cost: { key, _ in key.source.utf8.count * 4 })

    static func document(for source: String, home: String? = nil) -> MarkdownDocumentModel {
        let key = Key(source: source, home: home?.isEmpty == true ? nil : home)
        if let cached = table.value(for: key) { return cached }
        let document = MarkdownDocumentModel(source: source, home: key.home)
        table.setValue(document, for: key)
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

/// How authored destinations are rewritten and whether bare URLs become links (J2).
/// A value with no home and no autolinking is the historical parse.
struct MarkdownInlineContext: Sendable {
    var home: String?
    var linkingBareURLs = true

    /// A link to a local file becomes the app's `paseo-file:` URL — exactly what a
    /// linkified bare path is turned into, and what `ChatController.fileLinkAction`
    /// opens in the file viewer, so a tap on `[clip.mp4](/media/clip.mp4)` now opens the
    /// file instead of nothing. A scheme-less web destination gains `https://`. Anchors
    /// and `mailto:` are untouched.
    func destination(_ raw: String) -> String {
        guard home != nil else { return raw }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("mailto:"),
            RichLocalSource.filePath(trimmed, home: home) != nil
        else { return raw }
        return FilePathLinks.url(forPath: trimmed)?.absoluteString ?? raw
    }

    /// An image keeps its bare form when it is already something the image pipeline
    /// loads — a local path (absolute, `~/`, `./`; the pipeline resolves those itself —
    /// see `ProseMarkdownImage`) or a remote image URL. Only a local path written
    /// relative to the agent's working directory gets expanded, because nothing else
    /// would resolve it.
    func imageSource(_ raw: String) -> String {
        guard let home else { return raw }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") || trimmed.hasPrefix("./") {
            return raw
        }
        if RichContentDetector.isRemoteImageURL(trimmed) { return raw }
        guard case .file(let path)? = RichLocalSource.image(trimmed, home: home) else { return raw }
        return path
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
