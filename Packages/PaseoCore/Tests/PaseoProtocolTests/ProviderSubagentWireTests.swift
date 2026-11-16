import Foundation
import PaseoFixtures
import Testing

@testable import PaseoProtocol

/// E3 §1: provider subagent wire shapes.
///
/// `list_response` and `timeline_placeholder_response` are captured live from a daemon 0.16.0-beta.1
/// and scrubbed of ids and private text. The placeholder capture is the bug: without the
/// `projected_subagent_timeline` hello capability the daemon answers with one canned
/// "Please upgrade the Paseo app" row instead of the subagent's history.
/// `timeline_projected_schema` is shaped from the server's projected page
/// (`server/src/server/session.ts:8583-8615`), not captured: the live agent that has provider
/// subagents is a real Claude session this branch is not allowed to touch.
@Suite struct ProviderSubagentWireTests {
    let decoder = JSONDecoder()

    private func payload<T: Decodable & Sendable>(_ name: String, as: T.Type) throws -> T {
        let data = try Fixture.data(name, in: "provider-subagents")
        return try decoder.decode(SessionPayloadEnvelope<T>.self, from: data).payload
    }

    @Test func listFixtureDecodes() throws {
        let list = try payload("list_response", as: ProviderSubagentListRequest.Response.self)
        #expect(list.parentAgentId == "agent_parent_fixture")
        #expect(list.error == nil)
        #expect(list.subagents.count == 3)
        let running = list.subagents.filter { $0.status == .running }
        #expect(running.count == 1)
        #expect(list.subagents[1].title == "Explore")
        // The id is the provider's own; the tool call id matches it for Claude, not for every
        // provider, so nothing may assume they are the same field.
        #expect(list.subagents[0].id == "toolu_fixture_1")
    }

    @Test func placeholderTimelineDecodes() throws {
        let page = try payload(
            "timeline_placeholder_response", as: ProviderSubagentTimelineRequest.Response.self)
        #expect(page.rows.count == 1)
        #expect(page.staleCursor == false)
        #expect(page.window.maxSeq == 3)
        guard case .assistantMessage(let message) = page.rows[0].item else {
            Issue.record("expected the daemon's placeholder assistant message")
            return
        }
        #expect(message.text.hasPrefix("Please upgrade the Paseo app"))
    }

    @Test func projectedTimelineDecodes() throws {
        let page = try payload(
            "timeline_projected_schema", as: ProviderSubagentTimelineRequest.Response.self)
        #expect(page.hasOlder == true)
        #expect(page.rows.count == 5)
        #expect(page.rows.map(\.seq) == [1, 2, 4, 5, 6])
        #expect(page.rows[2].seqStart == 3)
        guard case .toolCall(let call) = page.rows[2].item else {
            Issue.record("expected a tool call row")
            return
        }
        #expect(call.status == .completed)
        guard case .shell(let command, _, let output, _) = call.detail else {
            Issue.record("expected a shell detail")
            return
        }
        #expect(command == "ls")
        #expect(output == "fixture.txt")
        guard case .assistantMessage(let answer) = page.rows[4].item else {
            Issue.record("expected the answer row")
            return
        }
        #expect(answer.text == "Fixture answer.")
    }

    @Test func unknownItemKindDoesNotFailThePage() throws {
        let page = try decoder.decode(
            ProviderSubagentTimelineRequest.Response.self,
            from: pageJSON(rows: [
                #"{"item":{"type":"assistant_message","text":"kept"},"seq":1,"timestamp":"t"}"#,
                #"{"item":{"type":"future_widget","payload":{"a":1}},"seq":2,"timestamp":"t"}"#,
            ]))
        #expect(page.rows.count == 2)
        guard case .assistantMessage = page.rows[0].item else {
            Issue.record("the known row must still decode")
            return
        }
        guard case .unknown(let type, let raw) = page.rows[1].item else {
            Issue.record("an unreadable item must become an unknown row")
            return
        }
        #expect(type == "future_widget")
        #expect(raw["payload"]?["a"] == .number(1))
    }

    @Test func malformedKnownItemDoesNotFailThePage() throws {
        // `tool_call` without its required `callId`: `TimelineItem` throws for it. One bad row
        // must not cost the page.
        let page = try decoder.decode(
            ProviderSubagentTimelineRequest.Response.self,
            from: pageJSON(rows: [
                #"{"item":{"type":"tool_call","name":"Bash","status":"completed","detail":{"type":"shell","command":"ls"}},"seq":1,"timestamp":"t"}"#,
                #"{"item":{"type":"assistant_message","text":"after"},"seq":2,"timestamp":"t"}"#,
                #"{"seq":3,"timestamp":"t"}"#,
            ]))
        #expect(page.rows.count == 3)
        guard case .unknown(let type, _) = page.rows[0].item else {
            Issue.record("a malformed tool call must become an unknown row")
            return
        }
        #expect(type == "tool_call")
        guard case .assistantMessage(let message) = page.rows[1].item else {
            Issue.record("the row after the bad one must still decode")
            return
        }
        #expect(message.text == "after")
        guard case .unknown(let missingType, _) = page.rows[2].item else {
            Issue.record("a row with no item must become an unknown row")
            return
        }
        #expect(missingType == "unsupported")
    }

    @Test func emptyTimelineDecodes() throws {
        // A daemon that sends only the documented minimum: everything optional keeps its default.
        let page = try decoder.decode(
            ProviderSubagentTimelineRequest.Response.self, from: Data(#"{"rows":[]}"#.utf8))
        #expect(page.rows.isEmpty)
        #expect(page.error == nil)
        #expect(page.epoch == "")
        #expect(page.hasOlder == nil)
        #expect(page.startCursor == nil)
        #expect(page.window.maxSeq == 0)
    }

    /// E3b: the sheet asks for the page before a cursor when the reader reaches the top.
    @Test func olderPageRequestEncodesDirectionAndCursor() throws {
        let request = ProviderSubagentTimelineRequest(
            parentAgentId: "agent_parent", subagentId: "toolu_1", direction: .before,
            cursor: TimelineCursor(epoch: "epoch_1", seq: 7), limit: 50)
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
        #expect(json["direction"] == .string("before"))
        #expect(json["cursor"]?["epoch"] == .string("epoch_1"))
        #expect(json["cursor"]?["seq"] == .number(7))
        #expect(json["limit"] == .number(50))
    }

    @Test func errorPageDecodes() throws {
        let json = """
            {"parentAgentId":"agent_parent_fixture","subagentId":"toolu_fixture_1",
             "epoch":"","reset":false,"staleCursor":false,"gap":false,
             "window":{"minSeq":0,"maxSeq":0,"nextSeq":0},
             "rows":[],"error":"Provider subagent not found"}
            """
        let page = try decoder.decode(
            ProviderSubagentTimelineRequest.Response.self, from: Data(json.utf8))
        #expect(page.error == "Provider subagent not found")
        #expect(page.rows.isEmpty)
    }

    private func pageJSON(rows: [String]) -> Data {
        let rowsJSON = rows.joined(separator: ",")
        return Data(
            """
            {"parentAgentId":"agent_parent_fixture","subagentId":"toolu_fixture_1",
             "epoch":"epoch_fixture","reset":false,"staleCursor":false,"gap":false,
             "window":{"minSeq":1,"maxSeq":3,"nextSeq":4},
             "rows":[\(rowsJSON)],"error":null}
            """.utf8)
    }
}
