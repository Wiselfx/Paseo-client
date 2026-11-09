import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// Regression for the M2.5a "a timeout message keeps appearing on the composer" bug.
///
/// Only the user's own send, cancel or settings change belongs in `actionError`, which the
/// composer renders. A failed background fetch (opening the conversation, an older page, catching
/// up after a gap) is kept in `backgroundError` so a slow or timed-out refresh never shows there.
@Suite @MainActor
struct ConversationBackgroundErrorTests {
    /// A tiny thread-safe flag: the fake client's handler runs off the main actor.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Bool

        init(_ value: Bool) { self.value = value }

        var current: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ newValue: Bool) {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    private func openStore(
        _ client: FakeDaemonClient,
        timeline: @escaping @Sendable (FetchAgentTimelineRequest) async throws ->
            FetchAgentTimelineRequest.Response
    ) async throws -> ConversationStore {
        let agents = try Load.agents()
        let agentId = try Load.fixtureAgentId()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline(timeline)
        client.onSetSubscription { _ in try Load.subscription() }

        let session = HostSession(client: client)
        await session.start()
        let store = session.conversation(for: agentId)
        let ready = await eventually { store.phase == .ready }
        #expect(ready)
        return store
    }

    @Test func aFailedOlderPageDoesNotReachTheComposer() async throws {
        let client = FakeDaemonClient()
        let store = try await openStore(client) { request in
            if request.direction == .before {
                throw FakeDaemonClient.FakeError.noHandler("older page")
            }
            var page = try Load.page()
            page.hasOlder = true
            return page
        }
        #expect(store.actionError == nil)

        await store.loadOlder()

        #expect(store.backgroundError != nil)
        #expect(store.actionError == nil, "background fetches stay off the composer")
    }

    @Test func aFailedReloadWithRowsOnScreenDoesNotReachTheComposer() async throws {
        let client = FakeDaemonClient()
        let store = try await openStore(client) { _ in try Load.page() }
        #expect(!store.timeline.rows.isEmpty)
        #expect(store.actionError == nil)

        client.onFetchTimeline { _ in throw FakeDaemonClient.FakeError.noHandler("reload") }
        await store.load()

        #expect(store.backgroundError != nil)
        #expect(store.actionError == nil)
        #expect(store.phase == .ready, "an existing conversation keeps its rows on a failed reload")
    }

    @Test func aSuccessfulBackgroundFetchClearsItsError() async throws {
        let client = FakeDaemonClient()
        let failOlderPages = Flag(true)
        let store = try await openStore(client) { request in
            if request.direction == .before, failOlderPages.current {
                throw FakeDaemonClient.FakeError.noHandler("older page")
            }
            var page = try Load.page()
            page.hasOlder = true
            return page
        }

        await store.loadOlder()
        #expect(store.backgroundError != nil)

        failOlderPages.set(false)
        await store.loadOlder()
        #expect(store.backgroundError == nil)
        #expect(store.actionError == nil)
    }
}
