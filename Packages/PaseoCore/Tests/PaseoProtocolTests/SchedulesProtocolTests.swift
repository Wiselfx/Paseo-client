import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

/// Decodes the schedule fixtures captured from a real daemon (`Tools/capture-schedules.mjs`) and
/// pins the request shapes the store sends.
@Suite
struct SchedulesProtocolTests {
    private let decoder = JSONDecoder()

    private func payload<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        try decoder.decode(SessionPayloadEnvelope<T>.self, from: Fixture.schedules(name)).payload
    }

    private func messageJSON<R: PaseoRequest>(_ request: R) throws -> [String: Any] {
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["message"] as? [String: Any])
    }

    // MARK: Responses

    @Test func listResponseDecodes() throws {
        let response = try payload("schedule_list_response", as: ScheduleListRequest.Response.self)
        #expect(response.error == nil)
        #expect(response.schedules.count == 1)
        let schedule = try #require(response.schedules.first)
        #expect(schedule.id == "a9bffe73")
        #expect(schedule.name == "T9 fixture schedule")
        #expect(schedule.prompt == "Reply with the single word: scheduled")
        #expect(schedule.status == .active)
        #expect(schedule.maxRuns == 2)
        #expect(schedule.expiresAt == nil)
        #expect(schedule.pausedAt == nil)
        #expect(schedule.nextRunAt == "2027-01-01T00:00:00.000Z")
        #expect(
            schedule.cadence == .cron(expression: "0 0 1 1 *", timezone: "UTC"))

        guard case .newAgent(let config) = schedule.target else {
            Issue.record("expected a new-agent target, got \(schedule.target)")
            return
        }
        #expect(config.provider == "omp")
        #expect(config.cwd == "/tmp/fixture-sandbox")
        #expect(config.model == "opencode-go/deepseek-v4.1-flash")
        #expect(config.modeId == "full")
        #expect(config.isolation == nil)
    }

    @Test func createResponseDecodes() throws {
        let response = try payload("schedule_create_response", as: ScheduleCreateRequest.Response.self)
        let schedule = try #require(response.schedule)
        #expect(schedule.id == "a9bffe73")
        #expect(schedule.name == "T9 fixture schedule")
        #expect(schedule.maxRuns == 2)
    }

    @Test func inspectResponseDecodesTheRunsArray() throws {
        let response = try payload("schedule_inspect_response", as: ScheduleInspectRequest.Response.self)
        let schedule = try #require(response.schedule)
        #expect(schedule.id == "a9bffe73")
        #expect(schedule.runs.isEmpty)
        #expect(schedule.summary.name == "T9 fixture schedule")
        #expect(schedule.lastRun == nil)
    }

    @Test func updateResponseDecodesTheEditedSchedule() throws {
        let response = try payload("schedule_update_response", as: ScheduleUpdateRequest.Response.self)
        let schedule = try #require(response.schedule)
        #expect(schedule.summary.name == "T9 fixture schedule renamed")
        #expect(schedule.summary.prompt == "Reply with the single word: rescheduled")
        #expect(schedule.summary.maxRuns == 3)
        #expect(
            schedule.summary.cadence == .cron(expression: "0 0 1 2 *", timezone: "UTC"))
        #expect(schedule.runs.isEmpty)
    }

    @Test func pauseAndResumeResponsesDecode() throws {
        let paused = try payload("schedule_pause_response", as: SchedulePauseRequest.Response.self)
        #expect(paused.schedule?.status == .paused)
        #expect(paused.schedule?.pausedAt != nil)
        #expect(paused.schedule?.nextRunAt == nil)

        let resumed = try payload("schedule_resume_response", as: ScheduleResumeRequest.Response.self)
        #expect(resumed.schedule?.status == .active)
        #expect(resumed.schedule?.pausedAt == nil)
        #expect(resumed.schedule?.nextRunAt == "2027-02-01T00:00:00.000Z")
    }

    @Test func logsResponseDecodesRunOutcomes() throws {
        let response = try payload("schedule_logs_response", as: ScheduleLogsRequest.Response.self)
        #expect(response.runs.count == 1)
        let run = try #require(response.runs.first)
        #expect(run.status == .succeeded)
        #expect(run.status.isTerminal)
        #expect(run.agentId == "517ffad9-6cec-4ec0-907f-6471f084a699")
        #expect(run.workspaceId == "wks_05b420ea4b0241b9")
        #expect(run.output == "rescheduled")
        #expect(run.error == nil)
        #expect(run.endedAt != nil)
    }

    @Test func runOnceResponseDecodesTheNewRun() throws {
        let response = try payload("schedule_run_once_response", as: ScheduleRunOnceRequest.Response.self)
        let schedule = try #require(response.schedule)
        #expect(schedule.runs.count == 1)
        #expect(schedule.lastRun?.status == .succeeded)
        #expect(schedule.summary.lastRunAt == "2026-11-08T23:12:21.353Z")
        #expect(schedule.summary.nextRunAt == "2027-02-01T00:00:00.000Z")
    }

    @Test func deleteResponseDecodes() throws {
        let response = try payload("schedule_delete_response", as: ScheduleDeleteRequest.Response.self)
        #expect(response.scheduleId == "a9bffe73")
        #expect(response.error == nil)
    }

    // MARK: Forward compatibility

    @Test func unknownEnumValuesDoNotThrow() throws {
        let status = try decoder.decode(
            ScheduleStatus.self, from: Data(#""expired""#.utf8))
        #expect(status == .unknown("expired"))

        let cadence = try decoder.decode(
            ScheduleCadence.self, from: Data(#"{"type":"lunar","phase":"full"}"#.utf8))
        #expect(cadence == .unknown("lunar"))

        let target = try decoder.decode(
            ScheduleTarget.self, from: Data(#"{"type":"orbit","planet":"mars"}"#.utf8))
        #expect(target == .unknown("orbit"))

        let runStatus = try decoder.decode(
            ScheduleRunStatus.self, from: Data(#""canceled""#.utf8))
        #expect(runStatus == .unknown("canceled"))
        #expect(!runStatus.isTerminal)
    }

    @Test func missingNullableFieldsDecodeAsNil() throws {
        let json = #"""
            {"id":"s1","prompt":"p","cadence":{"type":"every","everyMs":60000},
             "target":{"type":"agent","agentId":"a1"},"status":"active",
             "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"}
            """#
        let schedule = try decoder.decode(ScheduleSummary.self, from: Data(json.utf8))
        #expect(schedule.name == nil)
        #expect(schedule.nextRunAt == nil)
        #expect(schedule.lastRunAt == nil)
        #expect(schedule.pausedAt == nil)
        #expect(schedule.expiresAt == nil)
        #expect(schedule.maxRuns == nil)
        #expect(schedule.cadence == .every(everyMs: 60000))
        guard case .agent(let agentId) = schedule.target else {
            Issue.record("expected an agent target")
            return
        }
        #expect(agentId == "a1")
    }

    // MARK: Requests

    @Test func createRequestEncodesTheWireShape() throws {
        let request = ScheduleCreateRequest(
            prompt: "Reply with the single word: scheduled",
            cadence: .cron(expression: "0 0 1 1 *", timezone: "UTC"),
            target: .newAgent(
                ScheduleNewAgentConfig(
                    provider: "omp", cwd: "/tmp/fixture-sandbox",
                    modeId: "full", model: "opencode-go/deepseek-v4.1-flash")),
            name: "T9 fixture schedule",
            maxRuns: 2,
            runOnCreate: false)

        let message = try messageJSON(request)
        #expect(message["type"] as? String == "schedule/create")
        #expect(message["prompt"] as? String == "Reply with the single word: scheduled")
        #expect(message["name"] as? String == "T9 fixture schedule")
        #expect(message["maxRuns"] as? Int == 2)
        #expect(message["runOnCreate"] as? Bool == false)
        #expect(message["expiresAt"] == nil)

        guard let cadence = message["cadence"] as? [String: Any] else {
            Issue.record("missing cadence")
            return
        }
        #expect(cadence["type"] as? String == "cron")
        #expect(cadence["expression"] as? String == "0 0 1 1 *")
        #expect(cadence["timezone"] as? String == "UTC")

        guard let target = message["target"] as? [String: Any] else {
            Issue.record("missing target")
            return
        }
        #expect(target["type"] as? String == "new-agent")
        guard let config = target["config"] as? [String: Any] else {
            Issue.record("missing target config")
            return
        }
        #expect(config["provider"] as? String == "omp")
        #expect(config["cwd"] as? String == "/tmp/fixture-sandbox")
        #expect(config["model"] as? String == "opencode-go/deepseek-v4.1-flash")
        #expect(config["modeId"] as? String == "full")
        #expect(config["isolation"] == nil)
    }

    @Test func createRequestOmitsOptionalFieldsWhenNil() throws {
        let request = ScheduleCreateRequest(
            prompt: "p", cadence: .every(everyMs: 3_600_000),
            target: .agent(agentId: "a1"))
        let message = try messageJSON(request)
        #expect(message["name"] == nil)
        #expect(message["maxRuns"] == nil)
        #expect(message["expiresAt"] == nil)
        #expect(message["runOnCreate"] == nil)

        guard let cadence = message["cadence"] as? [String: Any] else {
            Issue.record("missing cadence")
            return
        }
        #expect(cadence["type"] as? String == "every")
        #expect(cadence["everyMs"] as? Int == 3_600_000)
    }

    @Test func selfTargetIsCreateOnlyAndEncodesAsSelf() throws {
        let request = ScheduleCreateRequest(
            prompt: "p", cadence: .cron(expression: "* * * * *", timezone: nil),
            target: .selfAgent(agentId: "a1"))
        let message = try messageJSON(request)
        guard let target = message["target"] as? [String: Any] else {
            Issue.record("missing target")
            return
        }
        #expect(target["type"] as? String == "self")
        #expect(target["agentId"] as? String == "a1")
    }

    @Test func updateRequestEncodesSetsAndClears() throws {
        let request = ScheduleUpdateRequest(
            scheduleId: "s1",
            name: .set("Renamed"),
            prompt: "Do the thing",
            cadence: .cron(expression: "0 0 1 2 *", timezone: "UTC"),
            newAgentConfig: ScheduleNewAgentConfigUpdate(
                provider: "omp",
                model: .clear,
                modeId: .set("ask"),
                thinkingOptionId: .clear,
                archiveOnFinish: true,
                isolation: .local,
                cwd: "/tmp/fixture-sandbox"),
            maxRuns: .clear,
            expiresAt: .set("2027-01-01T00:00:00.000Z"))

        let message = try messageJSON(request)
        #expect(message["type"] as? String == "schedule/update")
        #expect(message["scheduleId"] as? String == "s1")
        #expect(message["name"] as? String == "Renamed")
        #expect(message["prompt"] as? String == "Do the thing")
        #expect(message["maxRuns"] is NSNull)
        #expect(message["expiresAt"] as? String == "2027-01-01T00:00:00.000Z")

        guard let config = message["newAgentConfig"] as? [String: Any] else {
            Issue.record("missing newAgentConfig")
            return
        }
        #expect(config["provider"] as? String == "omp")
        #expect(config["model"] is NSNull)
        #expect(config["modeId"] as? String == "ask")
        #expect(config["thinkingOptionId"] is NSNull)
        #expect(config["archiveOnFinish"] as? Bool == true)
        #expect(config["isolation"] as? String == "local")
        #expect(config["cwd"] as? String == "/tmp/fixture-sandbox")
    }

    @Test func updateRequestOmitsUnchangedFields() throws {
        let request = ScheduleUpdateRequest(scheduleId: "s1")
        let message = try messageJSON(request)
        #expect(message["name"] == nil)
        #expect(message["prompt"] == nil)
        #expect(message["cadence"] == nil)
        #expect(message["newAgentConfig"] == nil)
        #expect(message["maxRuns"] == nil)
        #expect(message["expiresAt"] == nil)
    }

    @Test func simpleRequestsCarryOnlyTheirScheduleId() throws {
        let inspect = try messageJSON(ScheduleInspectRequest(scheduleId: "s1"))
        #expect(inspect["type"] as? String == "schedule/inspect")
        #expect(inspect["scheduleId"] as? String == "s1")

        let logs = try messageJSON(ScheduleLogsRequest(scheduleId: "s1"))
        #expect(logs["type"] as? String == "schedule/logs")

        let pause = try messageJSON(SchedulePauseRequest(scheduleId: "s1"))
        #expect(pause["type"] as? String == "schedule/pause")

        let resume = try messageJSON(ScheduleResumeRequest(scheduleId: "s1"))
        #expect(resume["type"] as? String == "schedule/resume")

        let runOnce = try messageJSON(ScheduleRunOnceRequest(scheduleId: "s1"))
        #expect(runOnce["type"] as? String == "schedule/run-once")

        let delete = try messageJSON(ScheduleDeleteRequest(scheduleId: "s1"))
        #expect(delete["type"] as? String == "schedule/delete")

        let list = try messageJSON(ScheduleListRequest())
        #expect(list["type"] as? String == "schedule/list")
        #expect(list["scheduleId"] == nil)
    }
}
