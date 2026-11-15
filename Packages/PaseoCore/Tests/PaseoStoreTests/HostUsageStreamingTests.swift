import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// A test-local box, so a handler that runs off the main actor can leave a value behind.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func with<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

/// How a host's report list arrives: one streamed report at a time, then a correlated response.
/// Upstream writes each report straight into what is on screen and settles the order afterwards
/// (`packages/app/src/usage/queries.ts:73-93`, `model.ts:51-99`); these tests hold the store to it.
@Suite @MainActor
struct HostUsageStreamingTests {
    private static func makeServerInfo() throws -> ServerInfo {
        let object: [String: Any] = [
            "serverId": "srv_STREAM_FIXTURE",
            "hostname": "fixture-host",
            "version": "0.16.0",
            "protocolVersion": 1,
            "features": ["usageSources": true],
        ]
        return try JSONDecoder().decode(
            ServerInfo.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func makeStore() throws -> (HostUsageStore, FakeDaemonClient) {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        client.on(GetDaemonConfigRequest.self) { _ in try Load.daemonConfig(enabled: true) }
        let store = HostUsageStore(client: client)
        store.update(serverInfo: try Self.makeServerInfo())
        return (store, client)
    }

    /// A captured update frame, re-addressed to the in-flight request.
    private nonisolated static func update(_ fixture: Data, requestId: String) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: fixture) as? [String: Any] ?? [:]
        var message = object["message"] as? [String: Any] ?? [:]
        var payload = message["payload"] as? [String: Any] ?? [:]
        payload["requestId"] = requestId
        message["payload"] = payload
        object["message"] = message
        return try JSONSerialization.data(withJSONObject: object)
    }

    private nonisolated static func response(error: String? = nil) throws
        -> UsageListReportsResponse
    {
        var object = try JSONSerialization.jsonObject(with: Fixture.usageListReportsResponse())
            as? [String: Any] ?? [:]
        var message = object["message"] as? [String: Any] ?? [:]
        var payload = message["payload"] as? [String: Any] ?? [:]
        payload["error"] = error ?? NSNull()
        message["payload"] = payload
        object["message"] = message
        return try JSONDecoder().decode(
            SessionPayloadEnvelope<UsageListReportsResponse>.self,
            from: try JSONSerialization.data(withJSONObject: object)).payload
    }

    @Test func aStreamedReportIsOnScreenBeforeTheResponseArrives() async throws {
        let (store, client) = try makeStore()
        let claude = try Fixture.usageReportAvailable()
        let seen = Locked<(phase: HostUsageStore.Phase?, count: Int)>((nil, 0))

        client.on(UsageListReportsRequest.self) { request in
            await MainActor.run {
                store.handle(
                    messageType: "usage.list_reports.update",
                    raw: try! Self.update(claude, requestId: request.requestId))
                seen.with { $0 = (store.phase, store.reports.count) }
            }
            return try Self.response()
        }

        let ok = await store.load()
        #expect(ok)
        let duringStream = seen.with { $0 }
        // The first report is drawn while the request is still open, not after the last source.
        #expect(duringStream.count == 1)
        #expect(duringStream.phase == .ready)
        #expect(store.reports.count == 1)
    }

    @Test func aReportTheHostNoLongerSendsLeavesTheList() async throws {
        let (store, client) = try makeStore()
        let claude = try Fixture.usageReportAvailable()
        let copilot = try Fixture.usageReportSecond()
        let script = Locked([claude, copilot])

        client.on(UsageListReportsRequest.self) { request in
            let fixtures = script.with { $0 }
            for fixture in fixtures {
                await MainActor.run {
                    store.handle(
                        messageType: "usage.list_reports.update",
                        raw: try! Self.update(fixture, requestId: request.requestId))
                }
            }
            return try Self.response()
        }

        _ = await store.load()
        #expect(store.reports.map(\.sourceId) == ["claude", "copilot"])

        // The next load streams only the second source; the stale card must go.
        script.with { $0 = [copilot] }
        _ = await store.load()
        #expect(store.reports.map(\.sourceId) == ["copilot"])
    }

    @Test func aFailedResponseWithReportsOnScreenKeepsTheCards() async throws {
        let (store, client) = try makeStore()
        let claude = try Fixture.usageReportAvailable()

        client.on(UsageListReportsRequest.self) { request in
            await MainActor.run {
                store.handle(
                    messageType: "usage.list_reports.update",
                    raw: try! Self.update(claude, requestId: request.requestId))
            }
            return try Self.response(error: "provider exploded")
        }

        let ok = await store.load()
        // Data on screen wins over the failed request (model.ts:131-140).
        #expect(ok)
        #expect(store.phase == .ready)
        #expect(store.error == "provider exploded")
        #expect(store.reports.count == 1)
    }

    @Test func aTransportFailureAfterAPartialStreamKeepsTheCards() async throws {
        let (store, client) = try makeStore()
        let claude = try Fixture.usageReportAvailable()

        client.on(UsageListReportsRequest.self) { request in
            await MainActor.run {
                store.handle(
                    messageType: "usage.list_reports.update",
                    raw: try! Self.update(claude, requestId: request.requestId))
            }
            throw ConnectionError.transport("socket exploded")
        }

        _ = await store.load()
        #expect(store.phase == .ready)
        #expect(store.error != nil)
        #expect(store.reports.count == 1)
    }

    @Test func pollingRunsEveryFiveMinutesAsUpstreamDoes() {
        #expect(HostUsageStore.automaticPollInterval == 300)
    }
}
