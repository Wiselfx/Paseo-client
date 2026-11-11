import Foundation
import Observation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// The schedules list polls because there are no push events. A quiet poll must not
/// republish the rows (every row would re-evaluate and the reader's scroll could suffer),
/// while a real change must still land.
@Suite @MainActor
struct SchedulesStorePollTests {
    private enum Fixtures {
        static func list() throws -> ScheduleListRequest.Response {
            try JSONDecoder().decode(
                SessionPayloadEnvelope<ScheduleListRequest.Response>.self,
                from: Fixture.schedules("schedule_list_response")
            ).payload
        }
    }

    /// One-shot observation counting: `Sendable` so it can cross the observation callback.
    private final class PublishCount: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    /// Serves one response per call: the fixture first, then the caller's override.
    private final class ListScript: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        let first: ScheduleListRequest.Response
        let second: ScheduleListRequest.Response

        init(first: ScheduleListRequest.Response, second: ScheduleListRequest.Response) {
            self.first = first
            self.second = second
        }

        func next() -> ScheduleListRequest.Response {
            lock.withLock {
                calls += 1
                return calls <= 1 ? first : second
            }
        }
    }

    @Test func identicalPollDoesNotRepublishTheList() async throws {
        let response = try Fixtures.list()
        let client = FakeDaemonClient()
        client.onSend(ScheduleListRequest.self) { _ in response }
        let store = SchedulesStore(client: client)
        await store.load()

        let publishes = PublishCount()
        withObservationTracking {
            _ = store.schedules
        } onChange: {
            publishes.increment()
        }
        await store.load()

        #expect(publishes.count == 0, "a quiet poll must not republish identical rows")
        #expect(store.phase == .ready)
        #expect(store.schedules == response.schedules)
    }

    @Test func changedPollReplacesTheList() async throws {
        var changed = try Fixtures.list()
        let schedule = try #require(changed.schedules.first)
        var renamed = schedule
        renamed.name = (schedule.name ?? "Schedule") + " (renamed)"
        changed.schedules[0] = renamed
        let script = ListScript(first: try Fixtures.list(), second: changed)
        let client = FakeDaemonClient()
        client.onSend(ScheduleListRequest.self) { _ in script.next() }
        let store = SchedulesStore(client: client)
        await store.load()

        let publishes = PublishCount()
        withObservationTracking {
            _ = store.schedules
        } onChange: {
            publishes.increment()
        }
        await store.load()

        #expect(publishes.count == 1, "a real change must still publish")
        #expect(store.schedules == changed.schedules)
    }
}
