import Foundation
import Testing
@testable import PaseoProtocol
@testable import PaseoStore

/// Ports of upstream `turn-collapse/model.test.ts` + `tool-calls/detail-level/overview/label.ts`
/// behaviour; copy verbatim from `i18n/resources/en.ts:2143-2175`.
@Suite struct TurnSummaryTests {
    @Test func countsEditedFilesDistinct() {
        let summary = TurnSummary(turn: makeTurn(rows: [
            makeToolCall(detail: .edit(filePath: "a.swift", oldString: nil, newString: nil, unifiedDiff: nil)),
            makeToolCall(detail: .edit(filePath: "a.swift", oldString: nil, newString: nil, unifiedDiff: nil)),
            makeToolCall(detail: .write(filePath: "b.swift", content: nil)),
        ]))
        #expect(summary.editedFileCount == 2)
        #expect(summary.overviewLabel == "Edited 2 files")
    }

    @Test func countsCommandsReadsSearchesAndOther() {
        let summary = TurnSummary(turn: makeTurn(rows: [
            makeToolCall(detail: .shell(command: "ls", cwd: nil, output: nil, exitCode: nil)),
            makeToolCall(detail: .shell(command: "pwd", cwd: nil, output: nil, exitCode: nil)),
            makeToolCall(detail: .read(filePath: "a.swift", content: nil)),
            makeToolCall(detail: .read(filePath: "a.swift", content: nil)),
            makeToolCall(detail: .search(makeSearch(query: "hello"))),
            makeToolCall(detail: .fetch(url: "https://example.com", result: nil, code: nil)),
        ]))
        #expect(summary.commandCount == 2)
        #expect(summary.readFileCount == 1)
        #expect(summary.searchCount == 1)
        #expect(summary.otherToolCount == 1)
        #expect(summary.overviewLabel == "Ran 2 commands, read 1 file, searched 1 time, and used 1 other tool")
    }

    @Test func singularAndPlural() {
        #expect(TurnSummary(commandCount: 1).overviewLabel == "Ran 1 command")
        #expect(TurnSummary(commandCount: 2).overviewLabel == "Ran 2 commands")
        #expect(TurnSummary(editedFileCount: 1).overviewLabel == "Edited 1 file")
        #expect(TurnSummary(readFileCount: 2).overviewLabel == "Read 2 files")
        #expect(TurnSummary(searchCount: 1).overviewLabel == "Searched 1 time")
        #expect(TurnSummary(searchCount: 2).overviewLabel == "Searched 2 times")
        #expect(TurnSummary(otherToolCount: 1).overviewLabel == "Used 1 other tool")
        #expect(TurnSummary(otherToolCount: 2).overviewLabel == "Used 2 other tools")
    }

    @Test func joinsTwoAndThreeParts() {
        #expect(TurnSummary(editedFileCount: 2, commandCount: 3).overviewLabel == "Edited 2 files and ran 3 commands")
        #expect(
            TurnSummary(editedFileCount: 1, commandCount: 1, readFileCount: 1).overviewLabel
                == "Edited 1 file, ran 1 command, and read 1 file"
        )
    }

    @Test func reasoningOnlyReadsThought() {
        let summary = TurnSummary(turn: makeTurn(rows: [makeReasoning(), makeReasoning()]))
        #expect(summary.thoughtCount == 2)
        #expect(summary.overviewLabel == "Thought")
        #expect(summary.detailsLabel == "Thought")
    }

    @Test func emptyFallsBackToViewTurnDetails() {
        let summary = TurnSummary()
        #expect(summary.overviewLabel.isEmpty)
        #expect(summary.detailsLabel == "View turn details")
        #expect(TurnSummary.viewTurnDetails == "View turn details")
    }

    @Test func aggregatesAcrossWorkGroups() {
        let summary = TurnSummary(turn: makeTurn(rows: [
            makeReasoning(),
            makeToolCall(detail: .shell(command: "ls", cwd: nil, output: nil, exitCode: nil)),
        ], splitWork: true))
        #expect(summary.thoughtCount == 1)
        #expect(summary.commandCount == 1)
        #expect(summary.overviewLabel == "Ran 1 command")
    }

    @Test func senderNameFallsBackToID() {
        #expect(TurnSummary.senderName(agentTitle: "Agent", senderTitle: "Sender", senderID: "id") == "Agent")
        #expect(TurnSummary.senderName(agentTitle: nil, senderTitle: "Sender", senderID: "id") == "Sender")
        #expect(TurnSummary.senderName(agentTitle: nil, senderTitle: nil, senderID: "id") == "id")
    }

    @Test func sentByInterpolatesName() {
        #expect(TurnSummary.sentByLabel(name: "PR helper") == "Sent by PR helper")
    }

    // MARK: - Fixtures

    private func makeTurn(rows: [TimelineRow], splitWork: Bool = false) -> Turn {
        if splitWork, rows.count == 2 {
            let prose = TimelineRow(id: "seq:900", turnId: "t1", item: .assistantMessage(.init(text: "mid")),
                                    timestamp: "", seqStart: 900, seqEnd: 900)
            let allRows = [rows[0], prose, rows[1]]
            return TurnBuilder.turns(from: allRows, activeTurnId: nil)[0]
        }
        return TurnBuilder.turns(from: rows, activeTurnId: nil)[0]
    }

    private func makeToolCall(detail: ToolCallDetail) -> TimelineRow {
        let id = UUID().uuidString
        let call = ToolCall(callId: "c-\(id)", name: "Tool", status: .completed, detail: detail, error: nil)
        return TimelineRow(id: "tool:c-\(id)", turnId: "t1", item: .toolCall(call), timestamp: "", seqStart: 0, seqEnd: 0)
    }

    private func makeReasoning() -> TimelineRow {
        let id = UUID().uuidString
        return TimelineRow(id: "seq:\(id)", turnId: "t1", item: .reasoning(.init(text: "hm")), timestamp: "", seqStart: 0, seqEnd: 0)
    }

    private func makeSearch(query: String) -> ToolCallDetail.Search {
        ToolCallDetail.Search(query: query, toolName: "search", content: nil, filePaths: nil, webResults: nil, numFiles: nil, numMatches: nil)
    }
}
