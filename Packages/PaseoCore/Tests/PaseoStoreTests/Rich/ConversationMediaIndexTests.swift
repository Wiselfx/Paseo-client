import Foundation
import Testing

@testable import PaseoProtocol
@testable import PaseoStore

// G12 C15: the conversation media index, maintained incrementally per turn.
struct ConversationMediaIndexTests {
    private func turn(id: String, text: String) -> Turn {
        let row = TimelineRow(
            id: "row:\(id)", turnId: id,
            item: .assistantMessage(TimelineItem.AssistantMessage(text: text, messageId: id)),
            timestamp: "2026-01-01T00:00:00Z", seqStart: 1, seqEnd: 2)
        let turns = TurnBuilder.turns(from: [
            TimelineRow(
                id: "u:\(id)", turnId: id,
                item: .userMessage(TimelineItem.UserMessage(text: "go")),
                timestamp: "2026-01-01T00:00:00Z", seqStart: 0, seqEnd: 0),
            row,
        ], activeTurnId: nil)
        #expect(turns.count == 1)
        return turns[0]
    }

    @Test("indexes images, diagrams, links and files by kind")
    func classifiesKinds() {
        // Bare URLs/paths only: authored `![alt](url)` images stay inline prose
        // (MarkdownImage), and inline links stay prose. The index mirrors what the
        // transcript turns into cards.
        let turn = turn(id: "t1", text: """
            https://example.com/plot.png
            ```mermaid
            graph TD; A-->B
            ```
            https://example.com/docs

            /tmp/report.pdf
            """)
        let index = ConversationMediaIndex()
        var mutable = index
        mutable.update(turns: [turn])
        let kinds = mutable.items.map(\.kind)
        #expect(kinds == [.image, .diagram, .link, .file])
        #expect(mutable.items[0].seqEnd == 2)
        #expect(mutable.items[0].turnID == turn.id)
        #expect(mutable.items[3].title == "report.pdf")
    }

    @Test("video and audio kinds")
    func mediaKinds() {
        let turn = turn(id: "t1", text: "/tmp/clip.mp4\n\n/tmp/note.m4a")
        var index = ConversationMediaIndex()
        index.update(turns: [turn])
        #expect(index.items.map(\.kind) == [.video, .audio])
    }

    @Test("incremental update equals a full rebuild")
    func incrementalEqualsFull() {
        let turns = [
            turn(id: "t1", text: "https://example.com/a.png"),
            turn(id: "t2", text: "nothing here"),
            turn(id: "t3", text: "/tmp/b.png\n\nhttps://example.com/c.png"),
        ]
        var incremental = ConversationMediaIndex()
        for (index, turn) in turns.enumerated() {
            incremental.update(turns: Array(turns.prefix(index + 1)))
        }
        var full = ConversationMediaIndex()
        full.update(turns: turns)
        #expect(incremental == full)
        #expect(full.items.count == 3)
    }

    @Test("a rewind rebuilds from scratch")
    func rewindRebuilds() {
        let turns = [
            turn(id: "t1", text: "https://example.com/a.png"),
            turn(id: "t2", text: "https://example.com/b.png"),
        ]
        var index = ConversationMediaIndex()
        index.update(turns: turns)
        #expect(index.items.count == 2)
        index.update(turns: [turns[0]])
        #expect(index.items.count == 1)
    }
}
