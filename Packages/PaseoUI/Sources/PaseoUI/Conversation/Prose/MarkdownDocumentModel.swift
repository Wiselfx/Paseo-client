import Foundation
import Markdown
import PaseoStore

/// Value-only rendering model. Parsing uses Swift's official CommonMark/GFM AST.
public struct MarkdownDocumentModel: Equatable, Sendable {
    public let source: String
    public var blocks: [MarkdownBlock]
    /// Whether any block — nested quotes and lists included — is a table. The tables own their
    /// viewport readers now (W8), so the renderer no longer gates on it; kept for hosts.
    /// Derived from `blocks`, so not part of `==`.
    public let hasTable: Bool
    /// Whether any block is a fenced code block. The code blocks own their expand sheets now
    /// (W8), so the renderer no longer gates on it; kept for hosts. Derived from `blocks`, so not
    /// part of `==`.
    public let hasCode: Bool
    /// Per-table content versions, by the table's document-unique path (Phase C §9.1; see
    /// `String.markdownChild`, nested tables included): a hash of the table's cell text,
    /// computed once per parse and memoised with the cached document. The layout remeasures
    /// when it changes (streamed text grows with the cell count unchanged); settled tables
    /// never change it, so steady state is still zero measurement.
    public var tableVersions: [String: Int]
    public init(source: String) {
        self.source = source
        let parsed = Document(parsing: source, options: [.disableSmartOpts]).children.map(
            MarkdownBlock.convert)
        blocks = parsed
        tableVersions = Self.tableVersions(for: parsed)
        let flags = Self.contentFlags(for: parsed)
        hasTable = flags.hasTable
        hasCode = flags.hasCode
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
        let flags = Self.contentFlags(for: parsed)
        hasTable = flags.hasTable
        hasCode = flags.hasCode
    }
    public init(source: String, blocks: [MarkdownBlock]) {
        self.source = source
        self.blocks = blocks
        tableVersions = Self.tableVersions(for: blocks)
        let flags = Self.contentFlags(for: blocks)
        hasTable = flags.hasTable
        hasCode = flags.hasCode
    }

    /// Which presenting hosts a document needs, in one O(blocks) walk of the parsed
    /// tree (nested quotes and lists included). Runs once per parse — the result is
    /// cached with the document — never per body pass.
    private static func contentFlags(for blocks: [MarkdownBlock]) -> (hasTable: Bool, hasCode: Bool) {
        var hasTable = false
        var hasCode = false
        func visit(_ blocks: [MarkdownBlock]) {
            for block in blocks {
                switch block {
                case .table: hasTable = true
                case .code: hasCode = true
                case .quote(let children): visit(children)
                case .list(_, let items):
                    for item in items { visit(item.blocks) }
                default: break
                }
                if hasTable, hasCode { return }
            }
        }
        visit(blocks)
        return (hasTable, hasCode)
    }

    private static func tableVersions(for blocks: [MarkdownBlock], path: String = "") -> [String: Int] {
        var versions: [String: Int] = [:]
        for (index, block) in blocks.enumerated() {
            let blockPath = path.markdownChild(index)
            switch block {
            case .table(let header, let rows, _):
                var hasher = Hasher()
                hasher.combine(rows.count)
                for cell in header { hasher.combine(cell.map(\.plainText).joined(separator: "\u{1F}")) }
                for row in rows {
                    for cell in row {
                        hasher.combine(cell.map(\.plainText).joined(separator: "\u{1F}"))
                    }
                }
                versions[blockPath] = hasher.finalize()
            case .quote(let children):
                versions.merge(Self.tableVersions(for: children, path: blockPath)) { _, nested in nested }
            case .list(_, let items):
                for (itemIndex, item) in items.enumerated() {
                    versions.merge(
                        Self.tableVersions(for: item.blocks, path: blockPath.markdownChild(itemIndex))
                    ) { _, nested in nested }
                }
            default: break
            }
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
    public static func cached(_ source: String, home: String? = nil) -> MarkdownDocumentModel {
        MarkdownDocumentCache.document(for: source, home: home)
    }

    /// The document for a streamed piece's intermediate text: read from the cache when present, never
    /// stored (see `RichPiecesCache.pieces(_:home:transient:)`).
    static func transient(_ source: String, home: String? = nil) -> MarkdownDocumentModel {
        MarkdownDocumentCache.document(for: source, home: home, store: false)
    }
}
