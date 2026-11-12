import Foundation
import Testing

@testable import PaseoProtocol
@testable import PaseoStore

// G6 C11: per-file line counts for a turn's edit/write calls.
struct TurnChangeSummaryTests {
    private func row(
        id: String, turnId: String = "t1", seq: Int = 0, detail: ToolCallDetail
    ) -> TimelineRow {
        TimelineRow(
            id: id, turnId: turnId,
            item: .toolCall(ToolCall(
                callId: id, name: "edit", status: .completed, detail: detail)),
            timestamp: "2026-01-01T00:00:00Z", seqStart: seq, seqEnd: seq)
    }

    private func turn(_ rows: [TimelineRow]) -> Turn {
        let turns = TurnBuilder.turns(from: rows, activeTurnId: nil)
        #expect(turns.count == 1)
        return turns[0]
    }

    /// Counts match `git diff --stat`: `+` lines (not `+++`), `-` lines (not `---`).
    @Test("unified diff counts match git diff --stat")
    func unifiedDiffCounts() throws {
        let diff = """
            --- a/Foo.swift
            +++ b/Foo.swift
            @@ -1,3 +1,4 @@
             context
            -removed one
            +added one
            +added two
             context
            \\ No newline at end of file
            """
        let summary = try #require(TurnChangeSummary.summarize(turn: turn([
            row(id: "c1", detail: .edit(
                filePath: "Foo.swift", oldString: nil, newString: nil, unifiedDiff: diff))
        ])))
        #expect(summary.files == [.init(path: "Foo.swift", added: 2, removed: 1)])
        #expect(summary.added == 2)
        #expect(summary.removed == 1)
    }

    /// No diff: line counts of the old/new strings (a full replace).
    @Test("edit without a diff falls back to line counts")
    func editWithoutDiffCountsLines() throws {
        let summary = try #require(TurnChangeSummary.summarize(turn: turn([
            row(id: "c1", detail: .edit(
                filePath: "a.txt", oldString: "one\ntwo\n", newString: "one\ntwo\nthree",
                unifiedDiff: nil))
        ])))
        #expect(summary.files == [.init(path: "a.txt", added: 3, removed: 2)])
    }

    /// A write counts as all added.
    @Test("write counts as all added")
    func writeCountsAsAllAdded() throws {
        let summary = try #require(TurnChangeSummary.summarize(turn: turn([
            row(id: "c1", detail: .write(filePath: "new.swift", content: "a\nb\nc\n"))
        ])))
        #expect(summary.files == [.init(path: "new.swift", added: 3, removed: 0)])
    }

    /// Repeated edits to one file sum into a single first-touched entry.
    @Test("repeated edits to one file sum in first-touched order")
    func repeatedEditsSum() throws {
        let summary = try #require(TurnChangeSummary.summarize(turn: turn([
            row(id: "c1", seq: 0, detail: .edit(
                filePath: "b.swift", oldString: "x", newString: "y", unifiedDiff: nil)),
            row(id: "c2", seq: 1, detail: .write(filePath: "a.swift", content: "z")),
            row(id: "c3", seq: 2, detail: .edit(
                filePath: "b.swift", oldString: "y", newString: "y\nz", unifiedDiff: nil)),
        ])))
        #expect(summary.files.map(\.path) == ["b.swift", "a.swift"])
        #expect(summary.files[0] == .init(path: "b.swift", added: 3, removed: 2))
        #expect(summary.added == 4)
        #expect(summary.removed == 2)
    }

    /// Non-edit calls never contribute, and a turn without edits has no summary.
    @Test("non-edit calls are ignored")
    func nonEditCallsIgnored() {
        let rows = [
            row(id: "c1", detail: .shell(
                command: "ls", cwd: nil, output: "a", exitCode: 0)),
            row(id: "c2", detail: .read(filePath: "a.txt", content: "hi")),
        ]
        #expect(TurnChangeSummary.summarize(turn: turn(rows)) == nil)
    }

    /// Incremental == full rebuild: streaming rows one at a time through the
    /// incremental builder yields exactly the full builder's summaries.
    @Test("incremental summaries equal a full rebuild")
    func incrementalEqualsFullRebuild() {
        let details: [ToolCallDetail] = [
            .edit(filePath: "a.swift", oldString: "x", newString: "y", unifiedDiff: nil),
            .write(filePath: "b.swift", content: "one\ntwo\n"),
            .edit(
                filePath: "a.swift", oldString: "y", newString: "y\nz",
                unifiedDiff: "@@ -1 +1,2 @@\n y\n+z\n"),
        ]
        var rows: [TimelineRow] = []
        let incremental = IncrementalTurnBuilder()
        for (index, detail) in details.enumerated() {
            rows.append(row(id: "c\(index)", detail: detail))
            let got = incremental.turns(from: rows, activeTurnId: nil)
            let want = TurnBuilder.turns(from: rows, activeTurnId: nil)
            #expect(got == want)
        }
        let summaries = incremental.turns(from: rows, activeTurnId: nil).compactMap(\.changeSummary)
        #expect(summaries.count == 1)
        #expect(summaries[0].files == [
            .init(path: "a.swift", added: 2, removed: 1),
            .init(path: "b.swift", added: 2, removed: 0),
        ])
    }
}
