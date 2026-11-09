import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct WorkspaceSetupTests {
    // MARK: Fixture decoding

    @Test func statusResponseDecodesRealSandboxTraffic() throws {
        // Real, scrubbed response captured from the sandbox: snapshot is null here because the
        // sandbox workspace has no setup script configured.
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<WorkspaceSetupStatusRequest.Response>.self,
            from: Fixture.data("workspace_setup_status_response", in: "workspace-setup")).payload
        #expect(response.snapshot == nil)
    }

    @Test func runResponseDecodesRealSandboxTraffic() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<WorkspaceSetupRunRequest.Response>.self,
            from: Fixture.data("workspace_setup_run_response", in: "workspace-setup")).payload
        #expect(response.started == false)
        #expect(response.error == nil)
    }

    @Test func subscribeResponseDecodesSyntheticFixture() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<WorkspaceSetupSubscribeRequest.Response>.self,
            from: Fixture.data("workspace_setup_subscribe_response", in: "workspace-setup")).payload
        #expect(response.subscriptionId == "subs_fixture_m210")
        let snapshot = try #require(response.snapshot)
        #expect(snapshot.status == .running)
        #expect(snapshot.detail.commands.count == 2)
        #expect(snapshot.detail.commands[0].status == .completed)
        #expect(snapshot.detail.commands[0].exitCode == 0)
        #expect(snapshot.detail.commands[0].durationMs == 1200)
        #expect(snapshot.detail.commands[1].status == .running)
        #expect(snapshot.detail.commands[1].exitCode == nil)
        #expect(snapshot.error == nil)
    }

    @Test func progressFrameDecodesSyntheticFixture() throws {
        let progress = try JSONDecoder().decode(
            SessionPayloadEnvelope<WorkspaceSetupProgress>.self,
            from: Fixture.data("workspace_setup_progress_failed", in: "workspace-setup")).payload
        #expect(progress.workspaceId == "wks_FIXTURE")
        #expect(progress.status == .failed)
        #expect(progress.detail.commands.count == 2)
        #expect(progress.error == "Command exited with code 1")
        #expect(progress.snapshot.status == .failed)
    }

    @Test func releaseResponseDecodesSyntheticFixture() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<SubscriptionReleaseRequest.Response>.self,
            from: Fixture.data("subscription_release_response", in: "workspace-setup")).payload
        #expect(response.subscriptionId == "subs_fixture_m210")
    }

    // MARK: Capabilities

    private func makeServerInfo(observation: Bool, run: Bool, owned: Bool) throws -> ServerInfo {
        let json = """
        {"serverId":"srv_FIXTURE","version":"0.15.2","features":{
          "workspaceSetupObservation":\(observation),"workspaceSetupRun":\(run),
          "ownedSubscriptions":\(owned)
        }}
        """
        return try JSONDecoder().decode(ServerInfo.self, from: Data(json.utf8))
    }

    @Test func capabilitiesComeFromServerInfo() async throws {
        let store = WorkspaceSetupObservationStore(client: FakeDaemonClient())
        #expect(!store.isSupported)
        store.update(serverInfo: try makeServerInfo(observation: true, run: true, owned: false))
        #expect(store.isSupported)
        #expect(store.capabilities.observation)
        #expect(store.capabilities.run)
        #expect(!store.capabilities.ownedSubscriptions)
    }

    // MARK: Status refresh

    @Test func refreshStoresTheSnapshot() async throws {
        let client = FakeDaemonClient()
        let data = try Fixture.data(
            "workspace_setup_subscribe_response", in: "workspace-setup")
        // Reuse the subscribe fixture's snapshot; status response carries the same shape.
        let subscribeJson = String(data: data, encoding: .utf8) ?? ""
        // Reuse the subscribe fixture as a status-response body: same payload shape.
        let statusJson = subscribeJson
            .replacingOccurrences(of: "\"workspace.setup.subscribe.response\"", with: "\"workspace_setup_status_response\"")
        client.on(WorkspaceSetupStatusRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<WorkspaceSetupStatusRequest.Response>.self,
                from: Data(statusJson.utf8)).payload
        }
        let store = WorkspaceSetupObservationStore(client: client)
        store.update(serverInfo: try makeServerInfo(observation: true, run: false, owned: false))
        await store.refresh("wks_FIXTURE")
        #expect(store.snapshot(for: "wks_FIXTURE")?.status == .running)
        #expect(store.error == nil)
    }

    @Test func refreshWithoutTheFeatureIsAnObservableError() async throws {
        let client = FakeDaemonClient()
        let store = WorkspaceSetupObservationStore(client: client)
        store.update(serverInfo: try makeServerInfo(observation: false, run: false, owned: false))
        await store.refresh("wks_FIXTURE")
        #expect(store.snapshot(for: "wks_FIXTURE") == nil)
        #expect(store.error == "This daemon cannot observe setup runs.")
        #expect(client.requests(WorkspaceSetupStatusRequest.self).isEmpty)
    }

    // MARK: Subscribe path

    @Test func subscribeStoresSnapshotAndIdWhenSupported() async throws {
        let client = FakeDaemonClient()
        let data = try Fixture.data(
            "workspace_setup_subscribe_response", in: "workspace-setup")
        client.on(WorkspaceSetupSubscribeRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<WorkspaceSetupSubscribeRequest.Response>.self, from: data).payload
        }
        // Use the subscribe path (owned subscriptions advertised); no status requests needed.
        let store = WorkspaceSetupObservationStore(client: client)
        store.update(serverInfo: try makeServerInfo(observation: true, run: true, owned: false))
        store.setOwnedSubscriptionCapabilityForTesting(true)
        await store.observe("wks_FIXTURE")
        #expect(store.snapshot(for: "wks_FIXTURE")?.status == .running)
        #expect(store.snapshot(for: "wks_FIXTURE")?.detail.commands.count == 2)
        #expect(client.requests(WorkspaceSetupSubscribeRequest.self).count == 1)
    }

    @Test func stopObservingReleasesTheSubscription() async throws {
        let client = FakeDaemonClient()
        let data = try Fixture.data(
            "workspace_setup_subscribe_response", in: "workspace-setup")
        client.on(WorkspaceSetupSubscribeRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<WorkspaceSetupSubscribeRequest.Response>.self, from: data).payload
        }
        client.on(SubscriptionReleaseRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<SubscriptionReleaseRequest.Response>.self,
                from: Fixture.data("subscription_release_response", in: "workspace-setup")).payload
        }
        let store = WorkspaceSetupObservationStore(client: client)
        store.update(serverInfo: try makeServerInfo(observation: true, run: true, owned: false))
        store.setOwnedSubscriptionCapabilityForTesting(true)
        await store.observe("wks_FIXTURE")
        await store.stopObserving("wks_FIXTURE")
        #expect(client.requests(SubscriptionReleaseRequest.self).count == 1)
        #expect(client.requests(SubscriptionReleaseRequest.self).first?.subscriptionId
            == "subs_fixture_m210")
    }

    @Test func progressFrameUpdatesTheSnapshot() async throws {
        let client = FakeDaemonClient()
        let store = WorkspaceSetupObservationStore(client: client)
        store.update(serverInfo: try makeServerInfo(observation: true, run: true, owned: true))
        let data = try Fixture.data("workspace_setup_progress_failed", in: "workspace-setup")
        store.handle(messageType: "workspace_setup_progress", raw: data)
        #expect(store.snapshot(for: "wks_FIXTURE")?.status == .failed)
        #expect(store.snapshot(for: "wks_FIXTURE")?.error == "Command exited with code 1")
        #expect(store.needsAttention("wks_FIXTURE"))
    }

    // MARK: Run setup again

    @Test func runSetupSendsTheRequestAndRefreshes() async throws {
        let client = FakeDaemonClient()
        let runResponse = Data("""
        {"type":"session","message":{"type":"workspace.setup.run.response","payload":{
          "requestId":"r","workspaceId":"wks_FIXTURE","started":true,"error":null
        }}}
        """.utf8)
        client.on(WorkspaceSetupRunRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<WorkspaceSetupRunRequest.Response>.self, from: runResponse).payload
        }
        let statusData = try Fixture.data(
            "workspace_setup_subscribe_response", in: "workspace-setup")
        let statusJson = (String(data: statusData, encoding: .utf8) ?? "")
            .replacingOccurrences(of: "workspace.setup.subscribe.response", with: "workspace_setup_status_response")
        client.on(WorkspaceSetupStatusRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<WorkspaceSetupStatusRequest.Response>.self,
                from: Data(statusJson.utf8)).payload
        }
        let store = WorkspaceSetupObservationStore(client: client)
        store.update(serverInfo: try makeServerInfo(observation: true, run: true, owned: false))
        let ok = await store.runSetup("wks_FIXTURE")
        #expect(ok == true)
        #expect(client.requests(WorkspaceSetupRunRequest.self).count == 1)
        // refresh happened as part of runSetup
        #expect(client.requests(WorkspaceSetupStatusRequest.self).count >= 1)
    }

    @Test func runSetupWithoutTheFeatureIsAnObservableError() async throws {
        let client = FakeDaemonClient()
        let store = WorkspaceSetupObservationStore(client: client)
        store.update(serverInfo: try makeServerInfo(observation: true, run: false, owned: false))
        let ok = await store.runSetup("wks_FIXTURE")
        #expect(ok == false)
        #expect(store.error == "This daemon cannot rerun setup.")
        #expect(client.requests(WorkspaceSetupRunRequest.self).isEmpty)
    }
}
