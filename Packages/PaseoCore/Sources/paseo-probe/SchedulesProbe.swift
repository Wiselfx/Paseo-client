import Foundation
import PaseoKit
import PaseoProtocol
import PaseoStore

// Live smoke test for T9. Creates one far-future new-agent schedule in /tmp/fixture-sandbox,
// inspects/updates/pauses/resumes it, runs it once, reads its logs and deletes it. The run creates
// an agent/workspace in the sandbox; the schedule archives the workspace, and this probe archives
// the run's agent too. It never touches anything outside /tmp/fixture-sandbox.
@MainActor
func runSchedules(_ connection: DaemonConnection) async throws {
    let sandbox = "/tmp/fixture-sandbox"
    try await connection.connect()

    let session = HostSession(client: connection)
    await session.start()
    let store = session.schedules
    guard store.isSupported else {
        throw ProbeError("host permissions do not include automation.manage")
    }

    await session.agentControl.loadCatalog(cwd: sandbox)
    guard let provider = session.agentControl.readyProviders.first(where: { $0.provider == "omp" })
        ?? session.agentControl.readyProviders.first
    else {
        throw ProbeError("no ready provider: \(session.agentControl.actionError ?? "unknown")")
    }
    let model = session.agentControl.defaultModel(forProvider: provider.provider)?.id
    let modes = session.agentControl.modes(forProvider: provider.provider).map(\.id)
    let mode = modes.first(where: { $0 == "full" }) ?? modes.first
    print(
        "provider=\(provider.provider) model=\(model ?? "-") mode=\(mode ?? "-")")

    await store.load()
    print("schedules before: \(store.schedules.count)  error=\(store.error ?? "none")")

    let draft = ScheduleDraft(
        name: "T9 probe schedule",
        prompt: "Reply with the single word: scheduled",
        cadence: .cron(expression: "0 0 1 1 *", timezone: "UTC"),
        target: .newAgent(
            ScheduleNewAgentConfig(
                provider: provider.provider, cwd: sandbox, modeId: mode, model: model)),
        maxRuns: 2)
    guard let created = await store.create(draft) else {
        throw ProbeError("create failed: \(store.actionError ?? "unknown")")
    }
    let scheduleId = created.id
    var runAgentId: String?
    var deleted = false
    print(
        "created \(scheduleId) status=\(created.status) next=\(created.nextRunAt ?? "-") maxRuns=\(created.maxRuns.map(String.init) ?? "-")")

    do {
        guard await store.inspect(scheduleId) else {
            throw ProbeError("inspect failed: \(store.actionError ?? "unknown")")
        }
        print(
            "inspect: name=\(store.selected?.summary.name ?? "-") runs=\(store.runs.count) cadence=\(cadenceText(store.selected?.summary.cadence))")

        guard
            await store.update(
                scheduleId,
                ScheduleEdits(
                    name: .set("T9 probe schedule renamed"),
                    prompt: "Reply with the single word: rescheduled",
                    maxRuns: .set(3),
                    newAgentConfig: ScheduleNewAgentConfigUpdate(model: .set(model ?? ""))))
        else {
            throw ProbeError("update failed: \(store.actionError ?? "unknown")")
        }
        print(
            "updated: name=\(store.selected?.summary.name ?? "-") prompt=\(store.selected?.summary.prompt ?? "-") maxRuns=\(store.selected?.summary.maxRuns.map(String.init) ?? "-")")

        guard await store.pause(scheduleId) else {
            throw ProbeError("pause failed: \(store.actionError ?? "unknown")")
        }
        print(
            "paused: status=\(store.schedule(id: scheduleId)?.status ?? .unknown("-")) next=\(store.schedule(id: scheduleId)?.nextRunAt ?? "-")")

        guard await store.resume(scheduleId) else {
            throw ProbeError("resume failed: \(store.actionError ?? "unknown")")
        }
        print(
            "resumed: status=\(store.schedule(id: scheduleId)?.status ?? .unknown("-")) next=\(store.schedule(id: scheduleId)?.nextRunAt ?? "-")")

        guard await store.loadLogs(scheduleId) else {
            throw ProbeError("logs failed: \(store.actionError ?? "unknown")")
        }
        print("logs before run: \(store.runs.count)")

        guard await store.runOnce(scheduleId) else {
            throw ProbeError("run once failed: \(store.actionError ?? "unknown")")
        }
        let run = store.runs.last
        runAgentId = run?.agentId
        print(
            "run once: status=\(runStatusText(run?.status)) agent=\(run?.agentId.map { String($0.prefix(8)) } ?? "-") output=\(oneLine(run?.output)) error=\(run?.error ?? "-")")

        guard await store.loadLogs(scheduleId) else {
            throw ProbeError("logs after run failed: \(store.actionError ?? "unknown")")
        }
        print("logs after run: \(store.runs.count)")

        if let agentId = runAgentId {
            _ = try? await connection.send(ArchiveAgentRequest(agentId: agentId))
            print("archived run agent \(String(agentId.prefix(8)))")
            runAgentId = nil
        }

        guard await store.delete(scheduleId) else {
            throw ProbeError("delete failed: \(store.actionError ?? "unknown")")
        }
        deleted = true
        print(
            "deleted \(scheduleId); schedules now: \(store.schedules.count) (contains=\(store.schedules.contains { $0.id == scheduleId }))")
    } catch {
        if !deleted {
            _ = try? await connection.send(ScheduleDeleteRequest(scheduleId: scheduleId))
            print("cleanup: deleted schedule \(scheduleId) after failure")
        }
        if let runAgentId {
            _ = try? await connection.send(ArchiveAgentRequest(agentId: runAgentId))
            print("cleanup: archived run agent \(String(runAgentId.prefix(8))) after failure")
        }
        throw error
    }
}

private func cadenceText(_ cadence: ScheduleCadence?) -> String {
    switch cadence {
    case .every(let everyMs): "every \(everyMs)ms"
    case .cron(let expression, let timezone): "cron \(expression) \(timezone ?? "-")"
    case .unknown(let raw): "unknown \(raw)"
    case nil: "-"
    }
}

private func runStatusText(_ status: ScheduleRunStatus?) -> String {
    switch status {
    case .running: "running"
    case .succeeded: "succeeded"
    case .failed: "failed"
    case .unknown(let raw): raw
    case nil: "-"
    }
}

private func oneLine(_ text: String?) -> String {
    guard let text, !text.isEmpty else { return "-" }
    return String(text.replacingOccurrences(of: "\n", with: " ").prefix(80))
}
