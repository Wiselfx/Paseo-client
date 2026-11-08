import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

@Suite struct TerminalStreamCodecTests {
    // MARK: Byte layout

    @Test func frameLayoutIsOpcodeSlotPayload() throws {
        let frame = TerminalStreamFrame(
            opcode: .output, slot: 7, payload: Data("hi".utf8))
        #expect([UInt8](frame.encoded) == [0x01, 0x07, 0x68, 0x69])

        let decoded = try #require(TerminalStreamFrame(decoding: frame.encoded))
        #expect(decoded.opcode == .output)
        #expect(decoded.slot == 7)
        #expect(decoded.payload == Data("hi".utf8))
    }

    @Test func shortFramesAreRejected() {
        #expect(TerminalStreamFrame(decoding: Data()) == nil)
        #expect(TerminalStreamFrame(decoding: Data([0x01])) == nil)
    }

    @Test func unknownOpcodeIsTolerated() throws {
        let frame = try #require(TerminalStreamFrame(decoding: Data([0x7f, 0x02, 0xaa])))
        #expect(frame.opcode == .unknown(0x7f))
        #expect(frame.slot == 2)
        #expect(frame.payload == Data([0xaa]))
    }

    @Test func everyKnownOpcodeRoundTrips() {
        let opcodes: [TerminalStreamOpcode] = [
            .output, .input, .resize, .snapshot, .restore, .replayBegin, .replayData, .replayEnd,
        ]
        for (index, opcode) in opcodes.enumerated() {
            let frame = TerminalStreamFrame(
                opcode: opcode, slot: UInt8(index), payload: Data([UInt8(index)]))
            let decoded = TerminalStreamFrame(decoding: frame.encoded)
            #expect(decoded?.opcode == opcode)
            #expect(decoded?.slot == UInt8(index))
            #expect(decoded?.payload == Data([UInt8(index)]))
        }
    }

    // MARK: Captured daemon stream

    @Test func capturedTerminalFramesDecodeInOrder() throws {
        let frames = try Fixture.terminalFrames()
        #expect(frames.map(\.opcode) == [0x06, 0x07, 0x08, 0x01, 0x01, 0x01])

        let begin = try #require(TerminalStreamFrame(decoding: frames[0].encoded))
        #expect(begin.opcode == .replayBegin)
        let metadata = try #require(begin.replayMetadata)
        #expect(metadata.rows == 24)
        #expect(metadata.cols == 80)
        #expect(metadata.retainedHistoryLines == 0)

        let replay = try #require(TerminalStreamFrame(decoding: frames[1].encoded))
        #expect(replay.opcode == .replayData)
        #expect(String(decoding: replay.payload, as: UTF8.self).contains("fixture-sandbox"))

        let end = try #require(TerminalStreamFrame(decoding: frames[2].encoded))
        #expect(end.opcode == .replayEnd)
        #expect(end.payload.isEmpty)

        let output = frames.filter { $0.opcode == 0x01 || $0.opcode == 0x07 }
            .map(\.payload)
            .reduce(into: Data()) { $0.append($1) }
        let text = String(decoding: output, as: UTF8.self)
        #expect(text.contains("hello\r\n"))
        #expect(text.contains("README.md"))

        // Same slot on every frame, which is what routes them to one view.
        #expect(Set(frames.map(\.slot)).count == 1)
    }

    @Test func legacyRestoreCarriesOneANSIPayload() throws {
        let frame = TerminalStreamFrame(
            opcode: .restore, slot: 3, payload: Data("\u{1B}[2Jrestored".utf8))
        let decoded = try #require(TerminalStreamFrame(decoding: frame.encoded))
        #expect(decoded.opcode == .restore)
        #expect(decoded.payload == Data("\u{1B}[2Jrestored".utf8))
    }

    // MARK: Outbound shapes

    @Test func terminalInputResizeEncodesFlatUnion() throws {
        let input = TerminalInput.resize(
            rows: 40, cols: 120, intent: .update, terminalId: "terminal-1")
        let object = try JSONDecoder().decode(
            JSONValue.self, from: JSONEncoder().encode(SessionOutboundEnvelope(input)))

        #expect(object["type"] == .string("session"))
        #expect(object["message"]?["type"] == .string("terminal_input"))
        #expect(object["message"]?["terminalId"] == .string("terminal-1"))
        #expect(object["message"]?["message"]?["type"] == .string("resize"))
        #expect(object["message"]?["message"]?["rows"] == .number(40))
        #expect(object["message"]?["message"]?["cols"] == .number(120))
        #expect(object["message"]?["message"]?["intent"] == .string("update"))
    }

    @Test func terminalInputDataIsAString() throws {
        let input = TerminalInput.input("ls\r", terminalId: "terminal-1")
        let object = try JSONDecoder().decode(
            JSONValue.self, from: JSONEncoder().encode(SessionOutboundEnvelope(input)))
        #expect(object["message"]?["message"]?["type"] == .string("input"))
        #expect(object["message"]?["message"]?["data"] == .string("ls\r"))
    }

    @Test func subscribeTerminalEncodesRestoreOptions() throws {
        var request = SubscribeTerminalRequest(
            terminalId: "terminal-1",
            restore: TerminalRestoreOptions(
                mode: .visibleSnapshot, scrollbackLines: 200,
                size: TerminalSize(rows: 24, cols: 80)))
        request.requestId = "request-1"

        let object = try JSONDecoder().decode(
            JSONValue.self, from: JSONEncoder().encode(SessionRequestEnvelope(request)))
        #expect(object["message"]?["type"] == .string("subscribe_terminal_request"))
        #expect(object["message"]?["requestId"] == .string("request-1"))
        #expect(object["message"]?["restore"]?["mode"] == .string("visible-snapshot"))
        #expect(object["message"]?["restore"]?["scrollbackLines"] == .number(200))
        #expect(object["message"]?["restore"]?["size"]?["rows"] == .number(24))
        #expect(object["message"]?["restore"]?["size"]?["cols"] == .number(80))
    }

    @Test func directorySubscribeIncludesWorkspaceAndCwd() throws {
        let request = SubscribeTerminalsRequest(cwd: "/tmp/fixture-sandbox", workspaceId: "ws-1")
        let object = try JSONDecoder().decode(
            JSONValue.self, from: JSONEncoder().encode(SessionOutboundEnvelope(request)))
        #expect(object["message"]?["type"] == .string("subscribe_terminals_request"))
        #expect(object["message"]?["workspaceId"] == .string("ws-1"))
        #expect(object["message"]?["cwd"] == .string("/tmp/fixture-sandbox"))
    }

    // MARK: Wire responses

    @Test func subscribeSuccessCarriesSlotAndFailureDoesNot() throws {
        let success = try JSONDecoder().decode(
            SessionPayloadEnvelope<SubscribeTerminalRequest.Response>.self,
            from: Fixture.terminalData("subscribe_terminal_response")
        ).payload
        #expect(success.error == nil)
        let slot = try #require(success.slot)
        #expect((0...255).contains(Int(slot)))
        #expect(success.terminalId.isEmpty == false)

        let failureJSON = """
            {"type":"session","message":{"type":"subscribe_terminal_response","payload":{
              "terminalId":"terminal-1","error":"Terminal not found","requestId":"r1"}}}
            """
        let failure = try JSONDecoder().decode(
            SessionPayloadEnvelope<SubscribeTerminalRequest.Response>.self,
            from: Data(failureJSON.utf8)
        ).payload
        #expect(failure.slot == nil)
        #expect(failure.subscriptionId == nil)
        #expect(failure.error == "Terminal not found")
    }

    @Test func createAndKillResponsesDecodeFromCapturedTraffic() throws {
        let created = try JSONDecoder().decode(
            SessionPayloadEnvelope<CreateTerminalRequest.Response>.self,
            from: Fixture.terminalData("create_terminal_response")
        ).payload
        let terminal = try #require(created.terminal)
        #expect(created.error == nil)
        #expect(terminal.name == "fixture-terminal")
        #expect(terminal.cwd == "/tmp/fixture-sandbox")
        #expect(terminal.workspaceId?.isEmpty == false)
        #expect(terminal.isScript == nil)
        #expect(terminal.activityBucket == nil)

        let killed = try JSONDecoder().decode(
            SessionPayloadEnvelope<KillTerminalRequest.Response>.self,
            from: Fixture.terminalData("kill_terminal_response")
        ).payload
        #expect(killed.success)
        #expect(killed.terminalId == terminal.id)
    }

    @Test func terminalsChangedReplacesTheWholeSnapshot() throws {
        let empty = try JSONDecoder().decode(
            SessionPayloadEnvelope<TerminalsChanged>.self,
            from: Fixture.terminalData("terminals_changed_000")
        ).payload
        #expect(empty.terminals.isEmpty)
        #expect(empty.cwd == "/tmp/fixture-sandbox")

        let one = try JSONDecoder().decode(
            SessionPayloadEnvelope<TerminalsChanged>.self,
            from: Fixture.terminalData("terminals_changed_001")
        ).payload
        #expect(one.terminals.count == 1)
        #expect(one.terminals.first?.name == "fixture-terminal")
        // The shipped daemon omits `workspaceId` on `terminals_changed` (upstream marks it
        // optional) and identifies the scope by `cwd`; the terminal row still carries it.
        #expect(one.workspaceId == nil)
        #expect(one.cwd == "/tmp/fixture-sandbox")
        #expect(one.terminals.first?.workspaceId?.isEmpty == false)
    }

    @Test func streamExitAndAttentionDecodeFromCapture() throws {
        let exit = try JSONDecoder().decode(
            SessionPayloadEnvelope<TerminalStreamExit>.self,
            from: Fixture.terminalData("terminal_stream_exit_000")
        ).payload
        #expect(exit.error == nil)
        #expect(exit.terminalId.isEmpty == false)

        let attentionJSON = """
            {"type":"session","message":{"type":"terminal_attention_required","payload":{
              "terminalId":"t1","cwd":"/tmp/x","workspaceId":"w1","reason":"needs_input",
              "title":"Terminal","body":"Needs input","shouldNotify":true}}}
            """
        let attention = try JSONDecoder().decode(
            SessionPayloadEnvelope<TerminalAttentionRequired>.self,
            from: Data(attentionJSON.utf8)
        ).payload
        #expect(attention.reason == .needsInput)
        #expect(attention.workspaceId == "w1")
    }

    // MARK: Activity buckets

    @Test func activityBucketsMatchUpstream() throws {
        func bucket(_ json: String) throws -> TerminalActivityBucket? {
            try JSONDecoder().decode(TerminalActivity.self, from: Data(json.utf8)).statusBucket
        }
        #expect(try bucket(#"{"state":"idle","changedAt":1}"#) == nil)
        #expect(try bucket(#"{"state":"working","changedAt":1}"#) == .running)
        #expect(try bucket(#"{"state":"attention","changedAt":1}"#) == .needsInput)
        #expect(
            try bucket(#"{"state":"idle","attentionReason":"finished","changedAt":1}"#) == .attention)
        #expect(
            try bucket(#"{"state":"idle","attentionReason":"needs_input","changedAt":1}"#)
                == .needsInput)
        // Unknown wire values degrade instead of throwing.
        #expect(try bucket(#"{"state":"plotting","changedAt":1}"#) == nil)
        let activity = try JSONDecoder().decode(
            TerminalActivity.self, from: Data(#"{"state":"x","attentionReason":"y","changedAt":1}"#.utf8))
        #expect(activity.state == .unknown("x"))
        #expect(activity.attentionReason == .unknown("y"))
    }

    // MARK: Scripts

    @Test func scriptListAndLifecycleDecodeFromCapture() throws {
        let list = try JSONDecoder().decode(
            SessionPayloadEnvelope<ListWorkspaceScriptsRequest.Response>.self,
            from: Fixture.terminalData("workspace_script_list_response", scenario: "scripts")
        ).payload
        let stopped = try #require(list.scripts?.first)
        #expect(list.error == nil)
        #expect(stopped.scriptName == "fixture")
        #expect(stopped.type == .script)
        #expect(stopped.lifecycle == .stopped)
        #expect(stopped.health == nil)
        #expect(stopped.hostname == "fixture")

        let started = try JSONDecoder().decode(
            SessionPayloadEnvelope<StartWorkspaceScriptRequest.Response>.self,
            from: Fixture.terminalData("workspace_script_start_response", scenario: "scripts")
        ).payload
        let running = try #require(started.script)
        #expect(started.error == nil)
        #expect(running.lifecycle == .running)
        #expect(running.terminalId?.isEmpty == false)
        // The shipped daemon returns `script` here; upstream says `scripts` carries the refreshed
        // list. The client accepts either.
        if let scripts = started.scripts {
            #expect(scripts.first?.lifecycle == .running)
        }

        let stoppedResponse = try JSONDecoder().decode(
            SessionPayloadEnvelope<StopWorkspaceScriptRequest.Response>.self,
            from: Fixture.terminalData("workspace_script_stop_response", scenario: "scripts")
        ).payload
        let afterStop = try #require(stoppedResponse.script)
        #expect(afterStop.lifecycle == .stopped)
        #expect(afterStop.exitCode == 0)
    }

    @Test func scriptStatusUpdateReplacesTheScriptsSnapshot() throws {
        let earlier = try JSONDecoder().decode(
            SessionPayloadEnvelope<ScriptStatusUpdate>.self,
            from: Fixture.terminalData("script_status_update_000", scenario: "scripts")
        ).payload
        #expect(earlier.scripts.first?.lifecycle == .running)

        let later = try JSONDecoder().decode(
            SessionPayloadEnvelope<ScriptStatusUpdate>.self,
            from: Fixture.terminalData("script_status_update_003", scenario: "scripts")
        ).payload
        #expect(later.scripts.first?.lifecycle == .stopped)
        #expect(later.scripts.first?.exitCode == 0)
    }

    @Test func unknownScriptValuesDoNotThrow() throws {
        let json = """
            {"scriptName":"x","type":"job","hostname":"fixture","port":null,"lifecycle":"paused",
             "health":"unknown","exitCode":null,"terminalId":null,"brandNew":true}
            """
        let script = try JSONDecoder().decode(WorkspaceScript.self, from: Data(json.utf8))
        #expect(script.type == .unknown("job"))
        #expect(script.lifecycle == .unknown("paused"))
        #expect(script.health == .unknown("unknown"))
        #expect(script.preferredURL == nil)
    }
}
