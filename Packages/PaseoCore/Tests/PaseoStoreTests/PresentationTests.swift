import Foundation
import Testing
import PaseoProtocol
@testable import PaseoStore

@Suite struct PresentationTests {
    @Test func fixtureToolCallsReadWell() throws {
        let calls = try Load.page().entries.compactMap { entry -> ToolCall? in
            if case .toolCall(let call) = entry.item { call } else { nil }
        }
        let rows = calls.map { ToolCallPresentation($0) }
        let shell = try #require(rows.first { $0.title == "Shell" })
        #expect(shell.subtitle == "ls -la")
        #expect(rows.contains { $0.title == "Read" && $0.subtitle == "convert.py" })
        #expect(rows.contains { $0.title == "Edit" && $0.subtitle == "convert.py" })
        #expect(rows.contains { $0.title == "Search" && $0.subtitle == "weather" })
        #expect(rows.allSatisfy { $0.status == .succeeded })
    }

    @Test func humanizesToolNames() {
        #expect(ToolCallPresentation.humanize("mcp__paseo__list_agents") == "List agents")
        #expect(ToolCallPresentation.humanize("Bash") == "Bash")
    }

    @Test func workSummary() {
        let thought = TimelineRow(id: "seq:1", turnId: "t", item: .reasoning(.init(text: "a")), timestamp: "", seqStart: 1, seqEnd: 1)
        #expect(Turn.WorkGroup(rows: [thought, thought]).summary == "2 thoughts")
    }
}
