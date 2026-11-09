import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// T17: every subscription path the daemon changes when the client advertises
/// `owned_subscriptions`. The modern signal on the wire is a server-assigned `subscriptionId`;
/// the legacy signal is its absence (the daemon strips it for legacy sockets). These tests drive
/// both shapes through `FakeDaemonClient`, so they hold for daemons on either side of the gate.
@Suite @MainActor
struct OwnedSubscriptionsTests {
    // MARK: Gate

    @Test func serverInfoWithoutTheFeatureKeepsTheLegacyPaths() throws {
        var info = try Load.serverInfo()
        #expect(info.supportsOwnedSubscriptions)
        info.features?["ownedSubscriptions"] = .bool(false)
        #expect(!info.supportsOwnedSubscriptions)
    }

    @Test func setupObservationOnlyTakesTheSubscribePathWhenTheDaemonSupportsIt() async throws {
        let client = FakeDaemonClient()
        let store = WorkspaceSetupObservationStore(client: client)
        var info = try Load.serverInfo()
        info.features?["ownedSubscriptions"] = .bool(false)
        store.update(serverInfo: info)
        #expect(!store.capabilities.ownedSubscriptions)

        store.update(serverInfo: try Load.serverInfo())
        #expect(store.capabilities.ownedSubscriptions)
    }

    // MARK: Terminals

    @Test func attachReleasesTheServerAssignedStreamId() async throws {
        let client = FakeDaemonClient()
        client.onSubscribeTerminal { _ in
            try Self.subscribeTerminalResponse(subscriptionId: "subs_terminal_1")
        }
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))

        let stream = await store.attach("t1", size: TerminalSize(rows: 24, cols: 80))
        #expect(store.subscriptionId(forTerminal: "t1") == "subs_terminal_1")

        store.detach("t1")
        #expect(store.subscriptionId(forTerminal: "t1") == nil)
        #expect(
            await eventually {
                client.requests(SubscriptionReleaseRequest.self).map(\.subscriptionId)
                    == ["subs_terminal_1"]
            })
        // A modern socket rejects the legacy detach with a handler error; it must not be sent.
        #expect(client.messages(of: UnsubscribeTerminalRequest.self).isEmpty)
        for await _ in stream {}
    }

    @Test func legacyAttachStillUsesTheLegacyDetach() async throws {
        let client = FakeDaemonClient()
        client.onSubscribeTerminal { _ in
            try Self.subscribeTerminalResponse(subscriptionId: nil)
        }
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))

        _ = await store.attach("t1", size: TerminalSize(rows: 24, cols: 80))
        #expect(store.subscriptionId(forTerminal: "t1") == nil)
        store.detach("t1")

        #expect(await eventually { !client.messages(of: UnsubscribeTerminalRequest.self).isEmpty })
        #expect(client.requests(SubscriptionReleaseRequest.self).isEmpty)
    }

    @Test func terminalDirectoryIsReleasedByOwnedId() async throws {
        let client = FakeDaemonClient()
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        await store.open(workspaceId: "w1", cwd: "/tmp/fixture-sandbox")

        // A modern socket tags every directory snapshot with its owned subscription id.
        store.handle(
            messageType: "terminals_changed",
            raw: try Self.terminalsChanged(workspaceId: "w1", subscriptionId: "subs_directory_1"))
        #expect(store.directorySubscriptionId(for: "w1") == "subs_directory_1")

        store.close(workspaceId: "w1")
        #expect(
            await eventually {
                client.requests(SubscriptionReleaseRequest.self).map(\.subscriptionId)
                    == ["subs_directory_1"]
            })
        #expect(client.messages(of: UnsubscribeTerminalsRequest.self).isEmpty)
        #expect(store.directorySubscriptionId(for: "w1") == nil)
    }

    @Test func legacyTerminalDirectoryStillUsesTheLegacyUnsubscribe() async throws {
        let client = FakeDaemonClient()
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        await store.open(workspaceId: "w1", cwd: "/tmp/fixture-sandbox")

        store.handle(
            messageType: "terminals_changed",
            raw: try Self.terminalsChanged(workspaceId: "w1", subscriptionId: nil))
        #expect(store.directorySubscriptionId(for: "w1") == nil)

        store.close(workspaceId: "w1")
        #expect(await eventually { !client.messages(of: UnsubscribeTerminalsRequest.self).isEmpty })
        #expect(client.requests(SubscriptionReleaseRequest.self).isEmpty)
    }

    @Test func terminalDirectorySubscribeCarriesARequestId() async throws {
        // A modern daemon refuses an owned subscription whose request has no `requestId`
        // ("Owned subscriptions require a requestId"), so the directory request must always
        // send one. Live 0.15.2 dropped it silently until this was fixed.
        let client = FakeDaemonClient()
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        await store.open(workspaceId: "w1", cwd: "/tmp/fixture-sandbox")

        let subscribed = client.messages(of: SubscribeTerminalsRequest.self)
        #expect(subscribed.count == 1)
        #expect(subscribed.first?.workspaceId == "w1")
        #expect(subscribed.first?.requestId?.isEmpty == false)
        store.close(workspaceId: "w1")
    }

    @Test func reconnectForgetsOwnedTerminalIds() async throws {
        let client = FakeDaemonClient()
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        await store.open(workspaceId: "w1", cwd: "/tmp/fixture-sandbox")
        store.handle(
            messageType: "terminals_changed",
            raw: try Self.terminalsChanged(workspaceId: "w1", subscriptionId: "subs_directory_1"))

        await store.handle(connection: .reconnecting(attempt: 1, lastError: .timeout))
        #expect(store.directorySubscriptionId(for: "w1") == nil)
        // Closing after a reconnect must not release an id the dead socket already lost, and
        // must not fall back to a legacy RPC the daemon rejects either.
        store.close(workspaceId: "w1")
        try await Task.sleep(for: .milliseconds(100))
        #expect(client.requests(SubscriptionReleaseRequest.self).isEmpty)
    }

    // MARK: Workspace setup

    @Test func setupObserveSubscribesAndReleasesOnStop() async throws {
        let client = FakeDaemonClient()
        let data = try Fixture.data("workspace_setup_subscribe_response", in: "workspace-setup")
        client.on(WorkspaceSetupSubscribeRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<WorkspaceSetupSubscribeRequest.Response>.self, from: data
            ).payload
        }
        let store = WorkspaceSetupObservationStore(client: client)
        store.update(serverInfo: try Load.serverInfo())

        await store.observe("wks_FIXTURE")
        #expect(store.snapshot(for: "wks_FIXTURE")?.status == .running)
        #expect(client.requests(WorkspaceSetupStatusRequest.self).isEmpty)

        await store.stopObserving("wks_FIXTURE")
        #expect(
            client.requests(SubscriptionReleaseRequest.self).map(\.subscriptionId)
                == ["subs_fixture_m210"])
    }

    @Test func setupResubscribesAfterReconnectAndDropsStaleIds() async throws {
        let client = FakeDaemonClient()
        let data = try Fixture.data("workspace_setup_subscribe_response", in: "workspace-setup")
        client.on(WorkspaceSetupSubscribeRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<WorkspaceSetupSubscribeRequest.Response>.self, from: data
            ).payload
        }
        let store = WorkspaceSetupObservationStore(client: client)
        store.update(serverInfo: try Load.serverInfo())
        await store.observe("wks_FIXTURE")

        await store.resubscribe()
        #expect(client.requests(WorkspaceSetupSubscribeRequest.self).count == 2)
        // The first subscription died with the socket; there is nothing to release on the new one.
        #expect(client.requests(SubscriptionReleaseRequest.self).isEmpty)
        #expect(store.snapshot(for: "wks_FIXTURE")?.detail.commands.count == 2)
    }

    // MARK: Workspace directory, labels, agents, timelines

    @Test func refreshingWorkspacesReleasesThePreviousSubscription() async throws {
        let client = FakeDaemonClient()
        let directory = WorkspaceDirectory(client: client)
        directory.update(serverInfo: try Load.workspaceServerInfo())
        let ids = Counter()
        client.on(FetchWorkspacesRequest.self) { _ in
            var response = try Load.workspaceDirectory()
            response.subscriptionId = "subs_workspaces_\(ids.next())"
            return response
        }
        client.on(ProjectListRequest.self) { _ in try Load.projectList() }

        await directory.reload()
        await directory.reload()
        #expect(
            await eventually {
                client.requests(SubscriptionReleaseRequest.self).map(\.subscriptionId)
                    == ["subs_workspaces_1"]
            })
    }

    @Test func reloadingLabelsReleasesThePreviousSubscription() async throws {
        let client = FakeDaemonClient()
        let store = WorkspaceLabelsStore(client: client)
        store.update(serverInfo: try Load.serverInfo())
        let ids = Counter()
        client.on(WorkspaceLabelListRequest.self) { request in
            try Self.labelListResponse(
                subscriptionId: request.subscribe == nil ? nil : "subs_labels_\(ids.next())")
        }

        await store.load()
        await store.load()
        #expect(
            await eventually {
                client.requests(SubscriptionReleaseRequest.self).map(\.subscriptionId)
                    == ["subs_labels_1"]
            })
    }

    @Test func refreshingAgentsReleasesThePreviousSubscription() async throws {
        let client = FakeDaemonClient()
        let ids = Counter()
        client.onFetchAgents { _ in
            var response = try Load.agents()
            response.subscriptionId = "subs_agents_\(ids.next())"
            return response
        }
        let session = HostSession(client: client)
        let info = try Load.serverInfo()
        await session.start()
        client.push(.connected(info))
        #expect(await eventually { session.serverInfo == info })

        await session.refreshAgents()
        #expect(
            await eventually {
                client.requests(SubscriptionReleaseRequest.self).map(\.subscriptionId)
                    == ["subs_agents_1"]
            })
    }

    @Test func changingTheViewedSetReleasesThePreviousTimelineSubscription() async throws {
        let client = FakeDaemonClient()
        let agentId = try Load.fixtureAgentId()
        let ids = Counter()
        client.onFetchAgents { _ in try Load.agents() }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { request in
            try Self.timelineSubscriptionResponse(
                agentIds: request.agentIds, subscriptionId: "subs_timeline_\(ids.next())")
        }
        let session = HostSession(client: client)
        let info = try Load.serverInfo()
        await session.start()
        client.push(.connected(info))
        #expect(await eventually { session.serverInfo == info })

        let store = session.conversation(for: agentId)
        #expect(await eventually { store.phase == .ready })
        #expect(
            await eventually {
                client.requests(SetAgentTimelineSubscriptionRequest.self).count == 1
            })
        session.closeConversation(agentId)

        // The closed agent must stop streaming: a modern daemon keeps the old subscription
        // alive (and delivering) until it is released.
        #expect(
            await eventually(timeout: .seconds(2)) {
                client.requests(SetAgentTimelineSubscriptionRequest.self).count == 2
            })
        #expect(
            await eventually {
                client.requests(SubscriptionReleaseRequest.self).map(\.subscriptionId)
                    == ["subs_timeline_1"]
            })
    }

    // MARK: Socket-wide events

    @Test func modernSocketSubscribesToTheEventPushesItNoLongerReceives() async throws {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.on(ProjectListRequest.self) { _ in try Load.projectList() }
        client.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }
        let session = HostSession(client: client)
        await session.start()

        let info = try Load.serverInfo()
        client.push(.connected(info))
        #expect(await eventually { session.ownedEvents.isSupported })
        #expect(
            await eventually {
                client.requests(SessionEventsSetSubscriptionRequest.self).contains {
                    Set(OwnedEventSubscription.baseEvents).isSubset(of: Set($0.events))
                }
            })

        client.push(.reconnecting(attempt: 1, lastError: .timeout))
        #expect(await eventually { session.ownedEvents.subscriptionId == nil })
        client.push(.connected(info))
        #expect(
            await eventually(timeout: .seconds(2)) {
                client.requests(SessionEventsSetSubscriptionRequest.self).filter {
                    Set(OwnedEventSubscription.baseEvents).isSubset(of: Set($0.events))
                }.count == 2
            })
    }

    // MARK: Fixtures

    nonisolated private static func subscribeTerminalResponse(
        subscriptionId: String?
    ) throws -> SubscribeTerminalRequest.Response {
        var payload: [String: Any] = [
            "terminalId": "t1", "slot": 3, "error": NSNull(), "requestId": "r",
        ]
        if let subscriptionId { payload["subscriptionId"] = subscriptionId }
        return try decode(
            type: "subscribe_terminal_response", payload: payload,
            expecting: SubscribeTerminalRequest.Response.self)
    }

    nonisolated private static func terminalsChanged(
        workspaceId: String, subscriptionId: String?
    ) throws -> Data {
        var payload: [String: Any] = [
            "cwd": "/tmp/fixture-sandbox", "workspaceId": workspaceId, "terminals": [],
        ]
        if let subscriptionId { payload["subscriptionId"] = subscriptionId }
        return try encode(type: "terminals_changed", payload: payload)
    }

    nonisolated private static func labelListResponse(
        subscriptionId: String?
    ) throws -> WorkspaceLabelListRequest.Response {
        var payload: [String: Any] = [
            "requestId": "r", "labels": [],
            "sync": ["generation": "g1", "headSeq": 0, "mode": "snapshot", "removals": []],
        ]
        if let subscriptionId { payload["subscriptionId"] = subscriptionId }
        return try decode(
            type: "workspace.label.list.response", payload: payload,
            expecting: WorkspaceLabelListRequest.Response.self)
    }

    nonisolated private static func timelineSubscriptionResponse(
        agentIds: [String], subscriptionId: String
    ) throws -> SetAgentTimelineSubscriptionRequest.Response {
        try decode(
            type: "agent.timeline.set_subscription.response",
            payload: [
                "requestId": "r", "agentIds": agentIds, "subscriptionId": subscriptionId,
            ],
            expecting: SetAgentTimelineSubscriptionRequest.Response.self)
    }

    nonisolated private static func encode(type: String, payload: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "type": "session", "message": ["type": type, "payload": payload],
            ])
    }

    nonisolated private static func decode<T: Decodable & Sendable>(
        type: String, payload: [String: Any], expecting: T.Type
    ) throws -> T {
        try JSONDecoder().decode(SessionPayloadEnvelope<T>.self, from: encode(type: type, payload: payload))
            .payload
    }
}

/// Small thread-safe sequence for responses that must differ per call (subscription ids).
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
