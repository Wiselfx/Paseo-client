import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// Drives `SchedulesStore` with the traffic captured by `Tools/capture-schedules.mjs` (one
/// far-future new-agent schedule in /tmp/fixture-sandbox).
@Suite @MainActor
struct SchedulesStoreTests {
    private enum Fixtures {
        static func payload<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
            try JSONDecoder().decode(
                SessionPayloadEnvelope<T>.self, from: Fixture.schedules(name)
            ).payload
        }

        static func list() throws -> ScheduleListRequest.Response {
            try payload("schedule_list_response", as: ScheduleListRequest.Response.self)
        }

        static func create() throws -> ScheduleCreateRequest.Response {
            try payload("schedule_create_response", as: ScheduleCreateRequest.Response.self)
        }

        static func inspect() throws -> ScheduleInspectRequest.Response {
            try payload("schedule_inspect_response", as: ScheduleInspectRequest.Response.self)
        }

        static func update() throws -> ScheduleUpdateRequest.Response {
            try payload("schedule_update_response", as: ScheduleUpdateRequest.Response.self)
        }

        static func pause() throws -> SchedulePauseRequest.Response {
            try payload("schedule_pause_response", as: SchedulePauseRequest.Response.self)
        }

        static func resume() throws -> ScheduleResumeRequest.Response {
            try payload("schedule_resume_response", as: ScheduleResumeRequest.Response.self)
        }

        static func logs() throws -> ScheduleLogsRequest.Response {
            try payload("schedule_logs_response", as: ScheduleLogsRequest.Response.self)
        }

        static func runOnce() throws -> ScheduleRunOnceRequest.Response {
            try payload("schedule_run_once_response", as: ScheduleRunOnceRequest.Response.self)
        }

        static func delete() throws -> ScheduleDeleteRequest.Response {
            try payload("schedule_delete_response", as: ScheduleDeleteRequest.Response.self)
        }

        static func summary() throws -> ScheduleSummary {
            let response = try list()
            guard let schedule = response.schedules.first else {
                throw Fixture.FixtureError.missing("schedules/schedule_list_response#schedule")
            }
            return schedule
        }

        static let sandbox = "/tmp/fixture-sandbox"
    }

    /// A store whose list is the captured sandbox schedule.
    private func loadedStore() async throws -> (FakeDaemonClient, SchedulesStore) {
        let client = FakeDaemonClient()
        client.onSend(ScheduleListRequest.self) { _ in try Fixtures.list() }
        let store = SchedulesStore(client: client)
        await store.load()
        return (client, store)
    }

    // MARK: List

    @Test func loadPopulatesTheList() async throws {
        let (_, store) = try await loadedStore()

        #expect(store.phase == .ready)
        #expect(store.error == nil)
        #expect(store.schedules.count == 1)
        let schedule = try #require(store.schedules.first)
        #expect(schedule.id == "a9bffe73")
        #expect(schedule.name == "T9 fixture schedule")
        #expect(schedule.status == .active)
        #expect(schedule.maxRuns == 2)
        #expect(store.schedule(id: "a9bffe73")?.id == schedule.id)
        #expect(store.schedule(id: "missing") == nil)
    }

    @Test func loadFailureSetsPhaseAndKeepsOldRows() async throws {
        let (client, store) = try await loadedStore()
        client.onSend(ScheduleListRequest.self) { _ in
            throw FakeDaemonClient.FakeError.noHandler("schedule/list")
        }

        await store.load()

        guard case .failed(let message) = store.phase else {
            Issue.record("expected a failed phase, got \(store.phase)")
            return
        }
        #expect(!message.isEmpty)
        #expect(store.error == message)
        #expect(store.schedules.count == 1, "a transient list error must not blank the screen")
    }

    @Test func daemonListErrorSetsPhase() async throws {
        let client = FakeDaemonClient()
        client.onSend(ScheduleListRequest.self) { _ in
            var response = try Fixtures.list()
            response.error = "permission denied"
            return response
        }
        let store = SchedulesStore(client: client)

        await store.load()

        #expect(store.phase == .failed("permission denied"))
        #expect(store.error == "permission denied")
        #expect(store.schedules.isEmpty)
    }

    // MARK: Inspect and logs

    @Test func inspectPopulatesSelectedAndRuns() async throws {
        let (client, store) = try await loadedStore()
        client.onSend(ScheduleInspectRequest.self) { _ in try Fixtures.inspect() }

        let inspected = await store.inspect("a9bffe73")

        #expect(inspected)
        #expect(store.actionError == nil)
        #expect(store.selectedId == "a9bffe73")
        #expect(store.selected?.summary.name == "T9 fixture schedule")
        #expect(store.selected?.runs.isEmpty == true)
        #expect(store.runs.isEmpty)
        #expect(client.requests(ScheduleInspectRequest.self).first?.scheduleId == "a9bffe73")
    }

    @Test func inspectFailureSetsActionError() async throws {
        let (client, store) = try await loadedStore()
        client.onSend(ScheduleInspectRequest.self) { _ in
            var response = try Fixtures.inspect()
            response.error = "Schedule not found"
            return response
        }

        let inspected = await store.inspect("missing")

        #expect(!inspected)
        #expect(store.actionError == "Schedule not found")
        #expect(store.selected == nil)
    }

    @Test func loadLogsPopulatesRuns() async throws {
        let (client, store) = try await loadedStore()
        client.onSend(ScheduleLogsRequest.self) { _ in try Fixtures.logs() }

        let loaded = await store.loadLogs("a9bffe73")

        #expect(loaded)
        #expect(store.selectedId == "a9bffe73")
        #expect(store.selected == nil, "logs alone do not claim a full schedule")
        #expect(store.runs.count == 1)
        #expect(store.runs.first?.status == .succeeded)
        #expect(store.runs.first?.output == "rescheduled")
        #expect(!store.isLoadingLogs)
    }

    // MARK: Create

    @Test func createSendsTheDraftAndInsertsTheSchedule() async throws {
        let client = FakeDaemonClient()
        client.onSend(ScheduleCreateRequest.self) { _ in try Fixtures.create() }
        let store = SchedulesStore(client: client)

        let created = await store.create(
            ScheduleDraft(
                name: "  T9 fixture schedule  ",
                prompt: "  Reply with the single word: scheduled  ",
                cadence: .cron(expression: "0 0 1 1 *", timezone: "UTC"),
                target: .newAgent(
                    ScheduleNewAgentConfig(
                        provider: "omp", cwd: Fixtures.sandbox,
                        modeId: "full", model: "opencode-go/deepseek-v4.1-flash")),
                maxRuns: 2))

        #expect(created?.id == "a9bffe73")
        #expect(store.lastCreated?.id == "a9bffe73")
        #expect(store.schedules.count == 1)
        #expect(store.actionError == nil)

        let request = try #require(client.requests(ScheduleCreateRequest.self).first)
        #expect(request.prompt == "Reply with the single word: scheduled", "prompt is trimmed")
        #expect(request.name == "T9 fixture schedule", "name is trimmed")
        #expect(request.maxRuns == 2)
        #expect(request.runOnCreate == nil, "false is omitted")
        #expect(request.cadence == .cron(expression: "0 0 1 1 *", timezone: "UTC"))
        guard case .newAgent(let config) = request.target else {
            Issue.record("expected a new-agent target")
            return
        }
        #expect(config.cwd == Fixtures.sandbox)
        #expect(config.provider == "omp")
    }

    @Test func createHeartbeatTargetsAnExistingAgent() async throws {
        let client = FakeDaemonClient()
        client.onSend(ScheduleCreateRequest.self) { _ in try Fixtures.create() }
        let store = SchedulesStore(client: client)

        _ = await store.createHeartbeat(
            agentId: "a1", prompt: "Check in", cron: "0 9 * * *", timezone: "UTC",
            name: "Heartbeat")

        let request = try #require(client.requests(ScheduleCreateRequest.self).first)
        #expect(request.target == .agent(agentId: "a1"))
        #expect(request.cadence == .cron(expression: "0 9 * * *", timezone: "UTC"))
        #expect(request.name == "Heartbeat")
    }

    @Test func createRejectsBlankPromptWithoutSending() async throws {
        let client = FakeDaemonClient()
        let store = SchedulesStore(client: client)

        let created = await store.create(
            ScheduleDraft(
                prompt: "   ", cadence: .cron(expression: "0 0 1 1 *", timezone: "UTC"),
                target: .agent(agentId: "a1")))

        #expect(created == nil)
        #expect(store.actionError == "A schedule prompt is required.")
        #expect(store.lastCreated == nil)
        #expect(client.requests.isEmpty)
    }

    @Test func createRejectsBlankCronAndNonPositiveMaxRuns() async throws {
        let client = FakeDaemonClient()
        let store = SchedulesStore(client: client)

        _ = await store.create(
            ScheduleDraft(
                prompt: "p", cadence: .cron(expression: "  ", timezone: nil),
                target: .agent(agentId: "a1")))
        #expect(store.actionError == "A cron expression is required.")

        _ = await store.create(
            ScheduleDraft(
                prompt: "p", cadence: .every(everyMs: 60_000),
                target: .agent(agentId: "a1"), maxRuns: 0))
        #expect(store.actionError == "Max runs must be a positive number.")
        #expect(client.requests.isEmpty)
    }

    @Test func createDaemonErrorIsSurfaced() async throws {
        let client = FakeDaemonClient()
        client.onSend(ScheduleCreateRequest.self) { _ in
            var response = try Fixtures.create()
            response.schedule = nil
            response.error = "cwd does not exist"
            return response
        }
        let store = SchedulesStore(client: client)

        let created = await store.create(
            ScheduleDraft(
                prompt: "p", cadence: .every(everyMs: 60_000),
                target: .agent(agentId: "a1")))

        #expect(created == nil)
        #expect(store.actionError == "cwd does not exist")
        #expect(store.schedules.isEmpty)
    }

    // MARK: Update

    @Test func updateSendsThePatchAndReplacesTheSummary() async throws {
        let (client, store) = try await loadedStore()
        client.onSend(ScheduleUpdateRequest.self) { _ in try Fixtures.update() }

        let updated = await store.update(
            "a9bffe73",
            ScheduleEdits(
                name: .set("T9 fixture schedule renamed"),
                prompt: "  Reply with the single word: rescheduled  ",
                cadence: .cron(expression: "0 0 1 2 *", timezone: "UTC"),
                maxRuns: .set(3),
                newAgentConfig: ScheduleNewAgentConfigUpdate(model: .clear)))

        #expect(updated)
        #expect(store.actionError == nil)
        #expect(store.schedules.count == 1)
        #expect(store.schedules.first?.name == "T9 fixture schedule renamed")
        #expect(store.schedules.first?.prompt == "Reply with the single word: rescheduled")
        #expect(store.selected?.summary.name == "T9 fixture schedule renamed")
        #expect(store.selectedId == "a9bffe73")

        let request = try #require(client.requests(ScheduleUpdateRequest.self).first)
        #expect(request.scheduleId == "a9bffe73")
        #expect(request.name == .set("T9 fixture schedule renamed"))
        #expect(request.prompt == "Reply with the single word: rescheduled")
        #expect(request.maxRuns == .set(3))
        #expect(request.cadence == .cron(expression: "0 0 1 2 *", timezone: "UTC"))
        #expect(request.newAgentConfig?.model == .clear)
    }

    @Test func updateRejectsBlankPromptWithoutSending() async throws {
        let (client, store) = try await loadedStore()

        let updated = await store.update("a9bffe73", ScheduleEdits(prompt: "   "))

        #expect(!updated)
        #expect(store.actionError == "A schedule prompt is required.")
        #expect(client.requests(ScheduleUpdateRequest.self).isEmpty)
    }

    // MARK: Pause, resume, delete

    @Test func pauseAndResumeReplaceTheRow() async throws {
        let (client, store) = try await loadedStore()
        client.onSend(SchedulePauseRequest.self) { _ in try Fixtures.pause() }
        client.onSend(ScheduleResumeRequest.self) { _ in try Fixtures.resume() }

        #expect(await store.pause("a9bffe73"))
        #expect(store.schedules.first?.status == .paused)
        #expect(store.schedules.first?.pausedAt != nil)
        #expect(store.schedules.first?.nextRunAt == nil)
        #expect(store.actionError == nil)

        #expect(await store.resume("a9bffe73"))
        #expect(store.schedules.first?.status == .active)
        #expect(store.schedules.first?.pausedAt == nil)
        #expect(store.schedules.first?.nextRunAt == "2027-02-01T00:00:00.000Z")
    }

    @Test func pauseDaemonErrorIsSurfaced() async throws {
        let (client, store) = try await loadedStore()
        client.onSend(SchedulePauseRequest.self) { _ in
            var response = try Fixtures.pause()
            response.schedule = nil
            response.error = "Schedule is already completed"
            return response
        }

        #expect(!(await store.pause("a9bffe73")))
        #expect(store.actionError == "Schedule is already completed")
        #expect(store.schedules.first?.status == .active, "the row is not changed optimistically")
    }

    @Test func runOnceLoadsTheRunAndUpdatesTheRow() async throws {
        let (client, store) = try await loadedStore()
        client.onSend(ScheduleRunOnceRequest.self) { _ in try Fixtures.runOnce() }

        #expect(await store.runOnce("a9bffe73"))
        #expect(store.selectedId == "a9bffe73")
        #expect(store.selected?.runs.count == 1)
        #expect(store.runs.count == 1)
        #expect(store.runs.first?.status == .succeeded)
        #expect(store.schedules.first?.lastRunAt == "2026-11-08T23:12:21.353Z")
        #expect(store.actionError == nil)
    }

    @Test func deleteRemovesTheRowAndSelection() async throws {
        let (client, store) = try await loadedStore()
        client.onSend(ScheduleInspectRequest.self) { _ in try Fixtures.inspect() }
        _ = await store.inspect("a9bffe73")
        client.onSend(ScheduleDeleteRequest.self) { _ in try Fixtures.delete() }

        let deleted = await store.delete("a9bffe73")

        #expect(deleted)
        #expect(store.schedules.isEmpty)
        #expect(store.selected == nil)
        #expect(store.selectedId == nil)
        #expect(store.runs.isEmpty)
        #expect(store.actionError == nil)
    }

    @Test func deleteFailureKeepsTheRow() async throws {
        let (client, store) = try await loadedStore()
        client.onSend(ScheduleDeleteRequest.self) { _ in
            var response = try Fixtures.delete()
            response.error = "Schedule not found"
            return response
        }

        #expect(!(await store.delete("a9bffe73")))
        #expect(store.actionError == "Schedule not found")
        #expect(store.schedules.count == 1)
    }

    // MARK: Capability

    @Test func isSupportedFollowsTheAutomationPermission() throws {
        let store = SchedulesStore(client: FakeDaemonClient())
        #expect(store.isSupported)

        var info = try Load.serverInfo()
        info.permissions = ["daemon.read", "workspace.read"]
        store.serverInfoChanged(info)
        #expect(!store.isSupported)

        info.permissions = ["automation.manage"]
        store.serverInfoChanged(info)
        #expect(store.isSupported)

        info.permissions = nil
        store.serverInfoChanged(info)
        #expect(store.isSupported, "a daemon that omits permissions is assumed capable")
    }

    // MARK: Derived state (doc 01 "Schedules" status pills)

    @Test func derivedStateCoversTheFiveBadges() throws {
        let now = try #require(PaseoDate.parse("2026-11-09T00:00:00.000Z"))

        var summary = try Fixtures.summary()
        #expect(summary.state(now: now) == .active)
        #expect(!ScheduleState.active.isEnded)

        summary.status = .paused
        #expect(summary.state(now: now) == .paused)
        #expect(!ScheduleState.paused.isEnded)

        summary.status = .completed
        #expect(summary.state(now: now) == .finished)
        #expect(ScheduleState.finished.isEnded)

        summary.status = .active
        summary.expiresAt = "2026-11-01T00:00:00.000Z"
        #expect(summary.state(now: now) == .expired, "expiry wins over the stored status")
        #expect(ScheduleState.expired.isEnded)

        summary.expiresAt = nil
        summary.target = .agent(agentId: "gone-agent")
        #expect(summary.state(now: now, knownAgentIds: []) == .targetGone)
        #expect(summary.state(now: now, knownAgentIds: ["gone-agent"]) == .active)
        #expect(summary.state(now: now, knownAgentIds: nil) == .active, "a cold agent cache proves nothing")
        #expect(ScheduleState.targetGone.isEnded)

        summary.status = .unknown("archived")
        summary.target = .newAgent(
            ScheduleNewAgentConfig(provider: "omp", cwd: Fixtures.sandbox))
        #expect(summary.state(now: now) == .unknown)
        #expect(!ScheduleState.unknown.isEnded)
    }

    @Test func storedScheduleDelegatesStateToItsSummary() throws {
        let response = try Fixtures.payload(
            "schedule_inspect_response", as: ScheduleInspectRequest.Response.self)
        let stored = try #require(response.schedule)
        let now = try #require(PaseoDate.parse("2026-11-09T00:00:00.000Z"))
        #expect(stored.state(now: now) == .active)
    }
}
