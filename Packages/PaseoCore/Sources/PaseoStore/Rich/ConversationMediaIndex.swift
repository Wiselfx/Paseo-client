import Foundation
import PaseoProtocol

// MARK: - ConversationMediaIndex (G12 C15)

// NOTE: RemoteImagePipeline/G12: "where was that screenshot?" The index answers from
// turn content alone: every assistant prose block is re-detected (the same pure
// detector the transcript uses) and media-bearing blocks become entries with their
// turn and row. Incremental: only turns added since the last update are scanned.

/// One media item in the conversation index: enough to render a grid tile or a row
/// and to jump back to the source turn.
public struct ConversationMediaItem: Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: Sendable, Equatable, Hashable {
        case image
        case video
        case audio
        case diagram
        case artifact
        case link
        case file
    }

    /// Stable across rebuilds: kind, location and turn.
    public var id: String
    public var kind: Kind
    /// What the tile/row shows: alt text, file name or domain.
    public var title: String
    /// The URL or daemon path, for opening.
    public var ref: String
    /// The turn that produced it (for the sheet's newest-first sort and the jump).
    public var turnID: String
    /// The row that holds it (for the scroll jump).
    public var seqEnd: Int

    public init(
        id: String, kind: Kind, title: String, ref: String, turnID: String, seqEnd: Int
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.ref = ref
        self.turnID = turnID
        self.seqEnd = seqEnd
    }
}

/// The conversation's media, maintained incrementally as turns complete: only turns
/// the index has not seen are scanned, so a streamed token never re-walks the chat.
///
/// Only the leading prefix of finished turns is covered: the running tail is scanned
/// when it completes (its text changes on every stream event, so covering it early
/// would scan it once per token and then never again). The id of the last covered
/// turn detects a same-count replacement (rewind, refresh) and rebuilds.
public struct ConversationMediaIndex: Sendable, Equatable {
    public private(set) var items: [ConversationMediaItem] = []
    /// How many leading turns `items` already covers.
    private var coveredTurnCount = 0
    /// The id of the last covered turn, for the same-count replacement check.
    private var lastCoveredTurnID: String?

    public init() {}

    /// Brings the index up to `turns`, scanning only the unseen finished tail.
    /// A shorter turn list, or a replaced one, rebuilds from scratch.
    public mutating func update(turns: [Turn]) {
        let finished = turns.prefix(while: { $0.phase != .running })
        let replaced = coveredTurnCount > 0
            && (finished.count < coveredTurnCount
                || finished.prefix(coveredTurnCount).last?.id != lastCoveredTurnID)
        if replaced {
            items = []
            coveredTurnCount = 0
            lastCoveredTurnID = nil
        }
        for turn in finished.dropFirst(coveredTurnCount) {
            items.append(contentsOf: Self.entries(for: turn))
        }
        coveredTurnCount = finished.count
        lastCoveredTurnID = finished.last?.id
    }

    /// Newest first: the sheet shows what just arrived at the top.
    public var newestFirst: [ConversationMediaItem] {
        items.reversed()
    }

    static func entries(for turn: Turn) -> [ConversationMediaItem] {
        var out: [ConversationMediaItem] = []
        for segment in turn.segments {
            guard case .prose(let row) = segment,
                case .assistantMessage(let message) = row.item
            else { continue }
            let blocks = RichContentDetector.detect(in: message.text)
            for block in blocks {
                if let item = entry(for: block, turnID: turn.id, seqEnd: row.seqEnd) {
                    out.append(item)
                }
            }
        }
        return out
    }

    private static func entry(
        for block: RichContentBlock, turnID: String, seqEnd: Int
    ) -> ConversationMediaItem? {
        let id: String
        let itemKind: ConversationMediaItem.Kind
        let title: String
        let ref: String
        switch block {
        case .bareImageURL(let url, _):
            id = "image:\(url)"
            itemKind = .image
            ref = url
            title = (url as NSString).lastPathComponent
        case .localImage(let path, let alt, _):
            id = "image:\(path)"
            itemKind = .image
            ref = path
            title = alt.isEmpty ? (path as NSString).lastPathComponent : alt
        case .localMedia:
            // The splice owns standalone media detection (it sees raw units); the
            // detector never emits this. Unreachable here.
            return nil
        case .remoteMedia:
            return nil
        case .mermaid(let source, _):
            id = "diagram:\(source.hashValue)"
            itemKind = .diagram
            ref = source
            title = "Diagram"
        case .visualize(let code, _):
            id = "artifact:\(code.hashValue)"
            itemKind = .artifact
            ref = code
            title = "Visualization"
        case .rawSVG(let source, _):
            id = "artifact:\(source.hashValue)"
            itemKind = .artifact
            ref = source
            title = "SVG"
        case .linkCard(let url, _):
            // A bare link with a playable extension is media, not a page.
            if let kind = RichStandaloneMedia.kindForURLString(url) {
                id = "media:\(url)"
                itemKind = kind == .video ? .video : .audio
                ref = url
                title = (url as NSString).lastPathComponent
            } else {
                id = "link:\(url)"
                itemKind = .link
                ref = url
                title = RichContentDetector.domain(for: url)
            }
        case .localFileLink(let path, _):
            // Same: a playable extension means a player card, in the transcript
            // (splice, G11) and here alike.
            if let kind = RichStandaloneMedia.kindForPath(path) {
                id = "media:\(path)"
                itemKind = kind == .video ? .video : .audio
                ref = path
                title = (path as NSString).lastPathComponent
            } else {
                id = "file:\(path)"
                itemKind = .file
                ref = path
                title = (path as NSString).lastPathComponent
            }
        case .youTubePlayer, .youTubeInline, .mapCard, .imageGroup:
            // YouTube opens inline from its card; maps open Apple Maps; galleries are
            // indexed by their members (the splice groups, the store lists).
            // Neither belongs in the media sheet as a unit.
            return nil
        }
        if title.isEmpty {
            return nil
        }
        return ConversationMediaItem(
            id: id, kind: itemKind, title: title, ref: ref, turnID: turnID, seqEnd: seqEnd)
    }
}
