import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// L3 Part D: the heartbeat carries the focused terminal. Upstream: `focusedTerminalId` on
/// `ClientHeartbeatMessageSchema` (packages/protocol/src/messages.ts:3169), sent on change by
/// packages/app/src/hooks/client-activity-tracker.ts:84-89.
@Suite @MainActor
struct HostSettingsTerminalFocusTests {
    private func heartbeats(_ client: FakeDaemonClient) -> [ClientHeartbeat] {
        client.messages.compactMap { $0 as? ClientHeartbeat }
    }

    @Test func focusingATerminalSendsItImmediately() async throws {
        let client = FakeDaemonClient()
        // Long interval: only explicit changes can add heartbeats during this test.
        let store = HostSettingsStore(client: client, heartbeatInterval: .seconds(30))
        store.startPresence(deviceType: .mobile, focusedAgentId: nil, appVisible: true)
        #expect(await eventually { heartbeats(client).count == 1 })

        store.updateTerminalFocus("term-1")
        #expect(await eventually { heartbeats(client).count == 2 })
        let sent = try #require(heartbeats(client).last)
        #expect(sent.focusedTerminalId == "term-1")
        #expect(sent.focusedAgentId == nil)
        #expect(store.focusedTerminalId == "term-1")
        store.stopPresence()
    }

    @Test func focusingAnAgentClearsTheTerminal() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client, heartbeatInterval: .seconds(30))
        store.startPresence(deviceType: .mobile, focusedAgentId: nil, appVisible: true)
        store.updateTerminalFocus("term-1")
        #expect(await eventually { heartbeats(client).count == 2 })

        store.updateFocus("agent-a")
        #expect(await eventually { heartbeats(client).count == 3 })
        let sent = try #require(heartbeats(client).last)
        #expect(sent.focusedAgentId == "agent-a")
        #expect(sent.focusedTerminalId == nil)
        #expect(store.focusedTerminalId == nil)
        store.stopPresence()
    }

    @Test func aStartingAgentFocusLeavesNoTerminal() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client, heartbeatInterval: .seconds(30))
        store.startPresence(deviceType: .mobile, focusedAgentId: "agent-a", appVisible: true)
        #expect(await eventually { heartbeats(client).count == 1 })
        let first = try #require(heartbeats(client).first)
        #expect(first.focusedAgentId == "agent-a")
        #expect(first.focusedTerminalId == nil)
        store.stopPresence()
    }

    @Test func aFocusedTerminalClearsTheAgentInTheSameHeartbeat() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client, heartbeatInterval: .seconds(30))
        store.startPresence(deviceType: .mobile, focusedAgentId: "agent-a", appVisible: true)
        #expect(await eventually { heartbeats(client).count == 1 })

        store.updateTerminalFocus("term-1")
        #expect(await eventually { heartbeats(client).count == 2 })
        let sent = try #require(heartbeats(client).last)
        #expect(sent.focusedAgentId == nil)
        #expect(sent.focusedTerminalId == "term-1")
        store.stopPresence()
    }

    @Test func anUnchangedTerminalSendsNothing() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client, heartbeatInterval: .seconds(30))
        store.startPresence(deviceType: .mobile, focusedAgentId: nil, appVisible: true)
        store.updateTerminalFocus("term-1")
        #expect(await eventually { heartbeats(client).count == 2 })

        store.updateTerminalFocus("term-1")
        try await Task.sleep(for: .milliseconds(50))
        #expect(heartbeats(client).count == 2, "the same terminal sends nothing")
        store.stopPresence()
    }

    @Test func leavingTheTerminalSendsNullAgainstTheTerminal() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client, heartbeatInterval: .seconds(30))
        store.startPresence(deviceType: .mobile, focusedAgentId: nil, appVisible: true)
        store.updateTerminalFocus("term-1")
        #expect(await eventually { heartbeats(client).count == 2 })

        store.updateTerminalFocus(nil)
        #expect(await eventually { heartbeats(client).count == 3 })
        #expect(heartbeats(client).last?.focusedTerminalId == nil)
        store.stopPresence()
    }

    @Test func aTerminalFocusedBeforePresenceIsOnlyStoredUntilPresenceStarts() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client, heartbeatInterval: .seconds(30))
        store.updateTerminalFocus("term-1")
        try await Task.sleep(for: .milliseconds(50))
        #expect(heartbeats(client).isEmpty)
        #expect(store.focusedTerminalId == "term-1")
    }

    @Test func absentTerminalIsEncodedAsNull() throws {
        let heartbeat = ClientHeartbeat(
            deviceType: .mobile, focusedAgentId: "agent-a", lastActivityAt: "2026-11-13T00:00:00.000Z",
            appVisible: true)
        let value = try JSONDecoder().decode(
            JSONValue.self, from: JSONEncoder().encode(heartbeat))
        #expect(value["focusedTerminalId"] == .null)
    }
}
