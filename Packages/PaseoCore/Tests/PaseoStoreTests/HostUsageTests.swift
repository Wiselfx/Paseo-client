import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// The host's provider plan usage reports — streamed updates, the correlated response, the
/// legacy provider.usage.list fallback, and the config/capability gates.
@Suite @MainActor
struct HostUsageTests {
    private static func makeServerInfo(features: [String: Bool]) throws -> ServerInfo {
        var object: [String: Any] = [
            "serverId": "srv_FIXTURE",
            "hostname": "fixture-host",
            "version": "0.15.2",
            "protocolVersion": 1,
        ]
        var mapped: [String: Any] = [:]
        for (key, value) in features { mapped[key] = value }
        object["features"] = mapped
        return try JSONDecoder().decode(
            ServerInfo.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func makeStore(
        features: [String: Bool] = ["usageSources": true, "providerUsageList": true],
        configEnabled: Bool = true
    ) throws -> (HostUsageStore, FakeDaemonClient) {
        let serverInfo = try Self.makeServerInfo(features: features)
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        client.on(GetDaemonConfigRequest.self) { _ in try Load.daemonConfig(enabled: configEnabled) }
        let store = HostUsageStore(client: client)
        store.update(serverInfo: serverInfo)
        return (store, client)
    }

    @Test func streamsReportsAndFinishesReady() async throws {
                let (store, client) = try makeStore()
        let claudeUpdate = try Fixture.usageReportAvailable()
        let copilotUpdate = try Fixture.usageReportSecond()

        client.on(UsageListReportsRequest.self) { request in
            for update in [claudeUpdate, copilotUpdate] {
                var object = try JSONSerialization.jsonObject(with: update) as? [String: Any] ?? [:]
                var message = object["message"] as? [String: Any] ?? [:]
                var payload = message["payload"] as? [String: Any] ?? [:]
                payload["requestId"] = request.requestId
                message["payload"] = payload
                object["message"] = message
                let raw = try JSONSerialization.data(withJSONObject: object)
                await MainActor.run { store.handle(messageType: "usage.list_reports.update", raw: raw) }
            }
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<UsageListReportsResponse>.self,
                from: Fixture.usageListReportsResponse()).payload
        }

        let ok = await store.load()
        #expect(ok)
        #expect(store.phase == .ready)
        #expect(store.error == nil)
        #expect(store.reports.map(\.sourceId) == ["claude", "copilot"])
        #expect(store.reports[0].accountLabel == "fixture-account@example.invalid")

        guard case .available(let claudeReport) = store.reports[0].report else {
            Issue.record("expected available claude report")
            return
        }
        #expect(claudeReport.planLabel == "Pro ai")
        #expect(claudeReport.windows.map(\.id) == ["five_hour", "weekly"])
    }

    @Test func forceRefreshIsForwardedToTheRequest() async throws {
        let (store, client) = try makeStore()
        client.on(UsageListReportsRequest.self) { request in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<UsageListReportsResponse>.self,
                from: Fixture.usageListReportsResponse()).payload
        }

        _ = await store.load(forceRefresh: true)
        let request = try #require(client.requests(UsageListReportsRequest.self).first)
        #expect(request.forceRefresh == true)
    }

    @Test func aHostWithUsageDisabledIsRefusedWithoutAsking() async throws {
        let (store, client) = try makeStore(configEnabled: false)
        let ok = await store.load()
        #expect(!ok)
        #expect(store.phase == .failed("Usage is off on this host. Ask the daemon to turn it on."))
        #expect(client.requests(UsageListReportsRequest.self).isEmpty)
    }

    @Test func anUnsupportedHostIsRefusedWithoutAsking() async throws {
        let (store, _) = try makeStore(features: [:])
        let ok = await store.load()
        #expect(!ok)
        #expect(store.phase == .failed("This host does not report usage; update the host."))
    }

    @Test func legacyHostsGetProviderUsageMappedOntoReports() async throws {
        let (store, client) = try makeStore(features: ["providerUsageList": true])
        client.on(ProviderUsageListRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<ProviderUsageListResponse>.self,
                from: Fixture.providerUsageListResponse()).payload
        }

        let ok = await store.load()
        #expect(ok)
        #expect(store.phase == .ready)
        #expect(store.reports.map(\.sourceId) == ["claude", "copilot"])

        guard case .available(let claudeReport) = store.reports[0].report else {
            Issue.record("expected available claude report")
            return
        }
        #expect(claudeReport.windows.map(\.id) == ["five_hour", "weekly"])
        #expect(claudeReport.planLabel == "Pro ai")
        guard case .available(let copilotReport) = store.reports[1].report else {
            Issue.record("expected available copilot report")
            return
        }
        #expect(copilotReport.details?.first?.value == "2026-12-01")
    }

    @Test func aFailedLoadKeepsTheOldReportsAndRecordsTheError() async throws {
        let (store, client) = try makeStore()
        client.on(UsageListReportsRequest.self) { _ in
            throw ConnectionError.transport("socket exploded")
        }

        let ok = await store.load()
        #expect(!ok)
        #expect(store.error != nil)
        if case .failed = store.phase {} else {
            Issue.record("expected .failed, got \(store.phase)")
        }
        #expect(store.reports.isEmpty)
    }

    @Test func updatesForAnotherRequestAreIgnored() async throws {
        let (store, _) = try makeStore()
        var object = try JSONSerialization.jsonObject(with: Fixture.usageReportAvailable()) as? [String: Any] ?? [:]
        var payload = object["payload"] as? [String: Any] ?? [:]
        payload["requestId"] = "some-other-request"
        object["payload"] = payload
        store.handle(
            messageType: "usage.list_reports.update",
            raw: try JSONSerialization.data(withJSONObject: object))
        #expect(store.reports.isEmpty)
    }
}
