#if canImport(UIKit)
import PaseoStore
import SwiftUI

// MARK: - Detail page

/// One schedule: its prompt, target, recent runs and the verbs for it. Pushed from the list, so
/// back is native; Delete pops back to the list when it succeeds.
struct ScheduleDetailPage: View {
    let session: HostSession
    let scheduleId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.toast) private var toast

    @State private var hasInspected = false
    @State private var confirmDelete = false

    private var schedules: SchedulesStore { session.schedules }
    private var stored: StoredSchedule? {
        schedules.selected?.id == scheduleId ? schedules.selected : nil
    }
    private var summary: ScheduleSummary? { stored?.summary ?? schedules.schedule(id: scheduleId) }
    private var knownAgentIds: Set<String> { Set(session.agents.map(\.id)) }
    private var state: ScheduleState? {
        summary?.state(now: Date(), knownAgentIds: knownAgentIds)
    }

    var body: some View {
        Group {
            if let summary {
                detail(summary)
            } else {
                LoadingState()
            }
        }
        .inlinePageTitle(summary.map(titleString) ?? "Schedule")
        .task {
            _ = await schedules.inspect(scheduleId)
            hasInspected = true
        }
        .refreshable { _ = await schedules.inspect(scheduleId) }
        .confirmationDialog(
            "Delete schedule?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Runs that already started finish, but no new runs will be created.")
        }
    }

    private func detail(_ summary: ScheduleSummary) -> some View {
        PageList {
            Section {
                hero(summary)
                    .panelRow(Palette.background)
            }
            Section {
                Text(summary.prompt)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.lg)
                    .textSelection(.enabled)
                    .panelRow()
            } header: {
                Text("Prompt")
            }
            Section {
                targetRows(summary)
            } header: {
                Text("Target")
            }
            Section {
                runsSection
            } header: {
                Text("Recent runs")
            }
            Section {
                actionRows(summary)
            } header: {
                Text("Actions")
            }
        }
    }

    // MARK: Hero

    private func hero(_ summary: ScheduleSummary) -> some View {
        VStack(spacing: Space.sm) {
            Image(systemName: "clock")
                .font(.glyph(.large, weight: .light))
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 48, height: 48)
                .background(Palette.panel, in: .circle)
            Text(titleString(summary))
                .font(.paseo(.title, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(summary.cadence.detailWords)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
            if let rawExpression = summary.cadence.detailRawExpression {
                Text(rawExpression)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.captionInk)
                    .multilineTextAlignment(.center)
            }
            if let state, state != .active {
                ScheduleStatePill(state: state)
            } else {
                Text(scheduleNextRun(summary.nextRunAt))
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.captionInk)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.lg)
    }

    // MARK: Target

    @ViewBuilder private func targetRows(_ summary: ScheduleSummary) -> some View {
        if let config = summary.target.newAgentConfig {
            newAgentRows(config)
        } else {
            agentRows(summary)
        }
    }

    @ViewBuilder private func newAgentRows(_ config: ScheduleNewAgentConfig) -> some View {
        infoRow("Workspace", value: workspaceName(cwd: config.cwd), detail: config.cwd)
        infoRow("Provider", value: providerLabel(config.provider))
        infoRow("Model", value: modelLabel(provider: config.provider, model: config.model))
        if config.modeId != nil {
            infoRow("Mode", value: modeLabel(provider: config.provider, mode: config.modeId))
        }
        if config.thinkingOptionId != nil {
            infoRow(
                "Thinking",
                value: thinkingLabel(
                    provider: config.provider, model: config.model, thinking: config.thinkingOptionId))
        }
        if config.archiveOnFinish == true {
            infoRow("Archive on finish", value: "On")
        }
    }

    @ViewBuilder private func agentRows(_ summary: ScheduleSummary) -> some View {
        let agentId = summary.target.agentId
        infoRow(
            "Heartbeat",
            value: agentTitle(agentId),
            detail: agentId.map { "Agent id: \($0)" })
        if let agentId,
            let workspaceId = session.agents.first(where: { $0.id == agentId })?.workspaceId,
            let workspace = session.workspaceDirectory.groups.flatMap(\.workspaces)
                .first(where: { $0.id == workspaceId })
        {
            infoRow("Workspace", value: workspace.name, detail: workspace.cwd)
        }
    }

    private func infoRow(_ title: String, value: String, detail: String? = nil) -> some View {
        ListRow(title: title, subtitle: detail, accessory: ListRow.Accessory.value(value))
            .panelRow()
    }

    private func workspaceName(cwd: String) -> String {
        for group in session.workspaceDirectory.groups {
            if let match = group.workspaces.first(where: { $0.cwd == cwd }) { return match.name }
        }
        return "Custom directory"
    }

    private func agentTitle(_ agentId: String?) -> String {
        guard let agentId else { return "Unknown agent" }
        return session.agents.first(where: { $0.id == agentId })?.title ?? agentId
    }

    private func providerLabel(_ providerId: String) -> String {
        session.agentControl.provider(providerId)?.label ?? providerId
    }

    private func modelLabel(provider: String, model: String?) -> String {
        guard let model else { return "Provider default" }
        if let match = session.agentControl.models(forProvider: provider).first(where: { $0.id == model }) {
            return match.label
        }
        return model
    }

    private func modeLabel(provider: String, mode: String?) -> String {
        guard let mode else { return "Provider default" }
        return session.agentControl.modes(forProvider: provider).first(where: { $0.id == mode })?.label
            ?? mode
    }

    private func thinkingLabel(provider: String, model: String?, thinking: String?) -> String {
        guard let thinking else { return "Provider default" }
        if let modelId = model ?? session.agentControl.defaultModel(forProvider: provider)?.id {
            return session.agentControl.thinkingOptions(forProvider: provider, modelId: modelId)
                .first(where: { $0.id == thinking })?.label ?? thinking
        }
        return thinking
    }

    // MARK: Runs

    @ViewBuilder private var runsSection: some View {
        if let stored, !stored.runs.isEmpty {
            ForEach(stored.runs) { run in
                runRow(run)
            }
        } else if !hasInspected {
            HStack {
                InlineProgress()
                Text("Loading…")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.lg)
            .panelRow()
        } else {
            Text("No runs yet.")
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.md)
                .panelRow()
        }
    }

    private func runRow(_ run: ScheduleRun) -> some View {
        HStack(spacing: Space.md) {
            Group {
                switch run.status {
                case .succeeded:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.successInk)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.failureInk)
                case .running, .unknown:
                    InlineProgress()
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(scheduleTimestamp(run.startedAt))
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.ink)
                if let error = run.error, !error.isEmpty {
                    Text(error)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.failureInk)
                        .lineLimit(2)
                } else if let output = run.output, !output.isEmpty {
                    Text(
                        output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
                            .first.map(String.init) ?? output
                    )
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
                }
            }
            Spacer(minLength: Space.xs)
            Text(scheduleDuration(run.startedAt, run.endedAt))
                .font(.paseo(.codeCaption))
                .foregroundStyle(Palette.captionInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .panelRow()
    }

    // MARK: Actions

    @ViewBuilder private func actionRows(_ summary: ScheduleSummary) -> some View {
        let isPaused = summary.status == .paused
        ListRow(title: isPaused ? "Resume schedule" : "Pause schedule") {
            Haptics.selection()
            Task { await setPaused(summary, paused: !isPaused) }
        }
        .panelRow()
        if summary.target.newAgentConfig != nil {
            ListRow(title: "Run now") {
                Haptics.selection()
                Task { await runNow(summary) }
            }
            .panelRow()
        }
        if let stored {
            NavigationLink(
                value: ClaudeSchedulesView.Route.editor(
                    ClaudeSchedulesView.EditorSeed(
                        stored: stored, isHeartbeat: stored.summary.target.agentId != nil))
            ) {
                ListRow(title: "Edit schedule", accessory: ListRow.Accessory.chevron)
            }
            .panelRow()
            .accessibilityLabel("Edit schedule")
        }
        Button(role: .destructive) {
            Haptics.selection()
            confirmDelete = true
        } label: {
            Text("Delete schedule")
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .panelRow()
    }

    private func setPaused(_ summary: ScheduleSummary, paused: Bool) async {
        let ok = paused
            ? await schedules.pause(summary.id)
            : await schedules.resume(summary.id)
        if ok {
            toast?.show(paused ? "Paused" : "Resumed")
            _ = await schedules.inspect(scheduleId)
        } else {
            toast?.show(schedules.actionError ?? "Couldn't update the schedule.")
        }
    }

    private func runNow(_ summary: ScheduleSummary) async {
        if await schedules.runOnce(summary.id) {
            toast?.show("Run started")
            _ = await schedules.inspect(scheduleId)
        } else {
            toast?.show(schedules.actionError ?? "Couldn't start a run.")
        }
    }

    private func delete() async {
        if await schedules.delete(scheduleId) {
            toast?.show("Schedule deleted")
            dismiss()
        } else {
            toast?.show(schedules.actionError ?? "Couldn't delete the schedule.")
        }
    }

    private func titleString(_ summary: ScheduleSummary) -> String {
        if let name = summary.name, !name.isEmpty { return name }
        let firstLine = summary.prompt.split(
            separator: "\n", maxSplits: 1, omittingEmptySubsequences: true
        ).first
        return firstLine.map(String.init) ?? "Schedule"
    }
}
#endif
