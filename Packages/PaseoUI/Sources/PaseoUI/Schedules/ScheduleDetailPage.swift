#if canImport(UIKit)
import PaseoStore
import SwiftUI

// MARK: - Detail page

struct ScheduleDetailPage: View {
    let session: HostSession
    let scheduleId: String
    let onBack: () -> Void
    let onEdit: (ClaudeSchedulesView.EditorSeed) -> Void
    let onDelete: (ScheduleSummary) -> Void
    let showToast: (String) -> Void

    @State private var hasInspected = false

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
        VStack(spacing: 0) {
            header
            content
        }
        .onAppear {
            Task {
                _ = await schedules.inspect(scheduleId)
                hasInspected = true
            }
        }
    }

    private var header: some View {
        ZStack {
            Text(summary.map(titleString) ?? "Schedule")
                .font(.paseo(.title, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: 200)
            HStack {
                Button {
                    Haptics.selection()
                    onBack()
                } label: {
                    Image(systemName: "chevron.left").font(.glyph(.large, weight: .light))
                        .frame(width: 42, height: 42)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Back")
                Spacer()
                Button("Edit") {
                    Haptics.selection()
                    if let stored {
                        let isHeartbeat = stored.summary.target.agentId != nil
                        onEdit(ClaudeSchedulesView.EditorSeed(stored: stored, isHeartbeat: isHeartbeat))
                    } else {
                        showToast("Still loading this schedule.")
                    }
                }
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.ink)
                .accessibilityLabel("Edit schedule")
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func titleString(_ summary: ScheduleSummary) -> String {
        if let name = summary.name, !name.isEmpty { return name }
        let firstLine = summary.prompt.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
        return firstLine.map(String.init) ?? "Schedule"
    }

    @ViewBuilder private var content: some View {
        if let summary {
            detail(summary)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detail(_ summary: ScheduleSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(summary)
                sectionLabel("Prompt")
                promptPanel(summary)
                sectionLabel("Target")
                RowGroup { targetRows(summary) }
                sectionLabel("Recent runs")
                runsSection
                sectionLabel("Actions")
                RowGroup { actionRows(summary) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Hero

    private func hero(_ summary: ScheduleSummary) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.glyph(.large, weight: .light))
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
        .padding(.vertical, 4)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.paseo(.caption2, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, 6)
    }

    private func promptPanel(_ summary: ScheduleSummary) -> some View {
        Text(summary.prompt)
            .font(.paseo(.callout))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
            .textSelection(.enabled)
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
        RowDivider()
        infoRow("Provider", value: providerLabel(config.provider))
        RowDivider()
        infoRow("Model", value: modelLabel(provider: config.provider, model: config.model))
        if config.modeId != nil {
            RowDivider()
            infoRow("Mode", value: modeLabel(provider: config.provider, mode: config.modeId))
        }
        if config.thinkingOptionId != nil {
            RowDivider()
            infoRow("Thinking", value: thinkingLabel(provider: config.provider, model: config.model, thinking: config.thinkingOptionId))
        }
        if config.archiveOnFinish == true {
            RowDivider()
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
           let workspace = session.workspaceDirectory.groups.flatMap(\.workspaces).first(where: { $0.id == workspaceId }) {
            RowDivider()
            infoRow("Workspace", value: workspace.name, detail: workspace.cwd)
        }
    }

    private func infoRow(_ title: String, value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.paseo(.callout))
                Spacer(minLength: 8)
                Text(value)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let detail {
                Text(detail)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.captionInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        return session.agentControl.modes(forProvider: provider).first(where: { $0.id == mode })?.label ?? mode
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
            RowGroup {
                ForEach(Array(stored.runs.enumerated()), id: \.element.id) { index, run in
                    if index > 0 { RowDivider() }
                    runRow(run)
                }
            }
        } else if !hasInspected {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else {
            Text("No runs yet.")
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }

    private func runRow(_ run: ScheduleRun) -> some View {
        HStack(spacing: 10) {
            Group {
                switch run.status {
                case .succeeded:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.successInk)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.failureInk)
                case .running, .unknown:
                    ProgressView().controlSize(.mini)
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
                    Text(output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? output)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            Text(scheduleDuration(run.startedAt, run.endedAt))
                .font(.paseo(.codeCaption))
                .foregroundStyle(Palette.captionInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: Actions

    @ViewBuilder private func actionRows(_ summary: ScheduleSummary) -> some View {
        let isPaused = summary.status == .paused
        Button {
            Haptics.selection()
            Task {
                let ok = isPaused ? await schedules.resume(summary.id) : await schedules.pause(summary.id)
                if ok {
                    showToast(isPaused ? "Resumed" : "Paused")
                    _ = await schedules.inspect(scheduleId)
                } else {
                    showToast(schedules.actionError ?? "Couldn't update the schedule.")
                }
            }
        } label: {
            actionRowLabel(isPaused ? "Resume schedule" : "Pause schedule", symbol: isPaused ? "play" : "pause")
        }
        .buttonStyle(.plain)
        if summary.target.newAgentConfig != nil {
            RowDivider()
            Button {
                Haptics.selection()
                Task {
                    if await schedules.runOnce(summary.id) {
                        showToast("Run started")
                        _ = await schedules.inspect(scheduleId)
                    } else {
                        showToast(schedules.actionError ?? "Couldn't start a run.")
                    }
                }
            } label: {
                actionRowLabel("Run now", symbol: "play.fill")
            }
            .buttonStyle(.plain)
        }
        RowDivider()
        Button {
            Haptics.selection()
            onDelete(summary)
        } label: {
            actionRowLabel("Delete schedule", symbol: "trash", destructive: true)
        }
        .buttonStyle(.plain)
    }

    private func actionRowLabel(_ title: String, symbol: String, destructive: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.glyph(.regular, weight: .light))
                .frame(width: 22)
                .foregroundStyle(destructive ? Palette.failureInk : Palette.ink)
            Text(title)
                .font(.paseo(.callout))
                .foregroundStyle(destructive ? Palette.failureInk : Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(.rect)
    }
}
#endif
