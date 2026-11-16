import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// H4 §2: the usage footer's throttle. `lastLoadedAt` is the only clock the store owns, and
/// `needsAutomaticLoad` is the one rule every caller (the sidebar's `.task`, a drawer open) asks.
@Suite @MainActor
struct HostUsageRefreshTests {
    private static func makeServerInfo(features: [String: Bool]) throws -> ServerInfo {
        var object: [String: Any] = [
            "serverId": "srv_REFRESH_FIXTURE",
            "hostname": "fixture-host",
            "version": "0.16.0",
            "protocolVersion": 1,
        ]
        object["features"] = features
        return try JSONDecoder().decode(
            ServerInfo.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func makeStore(
        features: [String: Bool] = ["providerUsageList": true],
        configEnabled: Bool = true
    ) throws -> (HostUsageStore, FakeDaemonClient) {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        client.on(GetDaemonConfigRequest.self) { _ in try Load.daemonConfig(enabled: configEnabled) }
        client.on(ProviderUsageListRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<ProviderUsageListResponse>.self,
                from: Fixture.providerUsageListResponse()).payload
        }
        let store = HostUsageStore(client: client)
        store.update(serverInfo: try Self.makeServerInfo(features: features))
        return (store, client)
    }

    @Test func nothingIsLoadedUntilTheFirstSuccess() async throws {
        let (store, _) = try makeStore()
        #expect(store.lastLoadedAt == nil)
        #expect(store.needsAutomaticLoad())

        let ok = await store.load()
        #expect(ok)
        #expect(store.lastLoadedAt != nil)
    }

    @Test func aFailedLoadLeavesTheClockUntouched() async throws {
        let (store, client) = try makeStore()
        client.on(ProviderUsageListRequest.self) { _ in
            throw ConnectionError.transport("socket exploded")
        }

        let ok = await store.load()
        #expect(!ok)
        #expect(store.lastLoadedAt == nil)
        // A failure is retried on the next trigger instead of being throttled away.
        #expect(store.needsAutomaticLoad())
    }

    @Test func aPolicyRefusalIsThrottledLikeAnAnswer() async throws {
        let (store, client) = try makeStore(configEnabled: false)
        let ok = await store.load()
        #expect(!ok)
        // The host answered ("off"), so the clock moves and a drawer open does not re-ask it.
        #expect(store.lastLoadedAt != nil)
        #expect(!store.needsAutomaticLoad())
        #expect(client.requests(ProviderUsageListRequest.self).isEmpty)
    }

    @Test func anUnsupportedHostNeverNeedsAnAutomaticLoad() async throws {
        let (store, _) = try makeStore(features: [:])
        #expect(!store.isSupported)
        #expect(!store.needsAutomaticLoad())

        let ok = await store.load()
        #expect(!ok)
        #expect(store.phase == .failed(HostUsageStore.unsupportedMessage))
        #expect(store.lastLoadedAt == nil)
    }

    @Test func theThrottleCountsFromTheLastSuccess() async throws {
        let (store, _) = try makeStore()
        _ = await store.load()
        let last = try #require(store.lastLoadedAt)

        #expect(!store.needsAutomaticLoad(now: last, minimumInterval: 60))
        #expect(!store.needsAutomaticLoad(now: last.addingTimeInterval(59), minimumInterval: 60))
        // The boundary itself is due: "at least a minute old", not "more than".
        #expect(store.needsAutomaticLoad(now: last.addingTimeInterval(60), minimumInterval: 60))
        #expect(store.needsAutomaticLoad(now: last.addingTimeInterval(600), minimumInterval: 60))
    }

    @Test func theDefaultIntervalIsAMinute() {
        #expect(HostUsageStore.automaticRefreshInterval == 60)
    }

    @Test func aSuccessfulLoadMovesTheClockForward() async throws {
        let (store, _) = try makeStore()
        _ = await store.load()
        let first = try #require(store.lastLoadedAt)

        _ = await store.load(forceRefresh: true)
        let second = try #require(store.lastLoadedAt)
        #expect(second >= first)
        // Fresh again: the forced load restarts the minute, so an open right after does no work.
        #expect(!store.needsAutomaticLoad(now: second, minimumInterval: 60))
    }
}
