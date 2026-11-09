#if canImport(UIKit)
import Combine
import PaseoStore
import SwiftUI
import UIKit

/// The Schedules screen: list what the daemon runs on a cadence, inspect a schedule's prompt and
/// run history, create or edit one, pause/resume, run once, delete. Backed by `SchedulesStore`
/// (`session.schedules`). Schedules have no push events, so the list polls on a timer while the
/// screen is open, and every page inspects/loads on appear. The page stack is hand-rolled — the
/// screen is a sheet, so there is no navigation bar.
struct ClaudeSchedulesView: View {
    let session: HostSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let typography = ClaudeTypography()

    /// What the editor opens with: nothing (a new schedule), or a stored schedule to edit. A
    /// heartbeat (`agent` target) edits only name, prompt, cadence and max runs.
    struct EditorSeed: Hashable {
        var stored: StoredSchedule?
        var isHeartbeat: Bool

        static let empty = EditorSeed(stored: nil, isHeartbeat: false)

        var title: String {
            guard stored != nil else { return "New schedule" }
            return isHeartbeat ? "Edit heartbeat" : "Edit schedule"
        }

        var scheduleId: String? { stored?.id }
    }

    enum Page: Hashable {
        case list
        case detail(String)
        case editor(EditorSeed)
    }

    @State private var page: Page = .list
    @State private var pendingDelete: ScheduleSummary?
    @State private var toast: String?

    private var schedules: SchedulesStore { session.schedules }

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .list:
                SchedulesListPage(
                    session: session, typography: typography, onClose: { dismiss() },
                    onOpen: { page = .detail($0) },
                    onNew: { page = .editor(.empty) },
                    showToast: showToast)
            case .detail(let id):
                ScheduleDetailPage(
                    session: session, typography: typography, scheduleId: id,
                    onBack: { page = .list },
                    onEdit: { seed in page = .editor(seed) },
                    onDelete: { summary in pendingDelete = summary },
                    showToast: showToast)
                .id(id)
            case .editor(let seed):
                ScheduleEditorPage(
                    session: session, typography: typography, seed: seed,
                    onBack: { page = seed.scheduleId.map { .detail($0) } ?? .list },
                    onCreated: { id in page = .detail(id) },
                    showToast: showToast)
                .id(seed)
            }
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear { Task { await schedules.load() } }
        .confirmationDialog(
            "Delete schedule?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let summary = pendingDelete else { return }
                pendingDelete = nil
                Task {
                    if await schedules.delete(summary.id) {
                        showToast("Schedule deleted")
                        page = .list
                    } else {
                        showToast(schedules.actionError ?? "Couldn't delete the schedule.")
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Runs that already started finish, but no new runs will be created.")
        }
        .overlay(alignment: .bottom) { toastView }
    }

    private var toastView: some View {
        Group {
            if let toast {
                Text(toast)
                    .font(typography.sans(13))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect()
                    .padding(.bottom, 18)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = nil }
        }
    }
}

/// The pill a row shows; active/paused/finished/expired/target gone, in warn or wash tints.
private struct ScheduleStatePill: View {
    let state: ScheduleState

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(ink.opacity(0.16), in: .rect(cornerRadius: 5))
            .accessibilityLabel(label)
    }

    private var label: String {
        switch state {
        case .active: "Active"
        case .paused: "Paused"
        case .expired: "Expired"
        case .finished: "Finished"
        case .targetGone: "Target gone"
        case .unknown: "Unknown"
        }
    }

    private var ink: Color {
        switch state {
        case .active: ClaudePalette.successInk
        case .paused: ClaudePalette.warning
        case .expired, .finished, .unknown: ClaudePalette.secondaryInk
        case .targetGone: ClaudePalette.failureInk
        }
    }
}

/// Formats an ISO-8601 instant ("2026-11-09T07:30:00Z") as "Nov 9, 09:12", or "—" otherwise.
private func scheduleTimestamp(_ iso: String?) -> String {
    guard let iso, let date = PaseoDate.parse(iso) else { return "—" }
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateFormat = "MMM d, HH:mm"
    return formatter.string(from: date)
}

/// "in 3h", "tomorrow at 09:00" for a next-run caption; "—" when missing.
private func scheduleNextRun(_ iso: String?) -> String {
    guard let iso, let date = PaseoDate.parse(iso) else { return "Not scheduled" }
    let seconds = date.timeIntervalSinceNow
    if seconds < 0 { return "Overdue" }
    if seconds < 3600 { return "In \(max(1, Int(seconds / 60))) min" }
    if seconds < 86_400 { return "In \(Int(seconds / 3600))h" }
    let days = Int(seconds / 86_400)
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateFormat = "MMM d, HH:mm"
    return days == 1 ? "Tomorrow at \(formatter.string(from: date))" : "In \(days) days · \(formatter.string(from: date))"
}

private func scheduleDuration(_ start: String, _ end: String?) -> String {
    guard let startDate = PaseoDate.parse(start) else { return "—" }
    let endDate = end.flatMap(PaseoDate.parse) ?? Date()
    let seconds = max(0, endDate.timeIntervalSince(startDate))
    if seconds < 1 { return "<1s" }
    if seconds < 60 { return "\(Int(seconds))s" }
    return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s"
}

// MARK: - List page

private struct SchedulesListPage: View {
    let session: HostSession
    let typography: ClaudeTypography
    let onClose: () -> Void
    let onOpen: (String) -> Void
    let onNew: () -> Void
    let showToast: (String) -> Void

    @State private var now = Date()
    private let poll = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var schedules: SchedulesStore { session.schedules }
    private var knownAgentIds: Set<String> { Set(session.agents.map(\.id)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let actionError = schedules.actionError {
                Text(actionError)
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            content
        }
        .onReceive(poll) { date in
            now = date
            Task { await schedules.load() }
        }
    }

    private var header: some View {
        ZStack {
            Text("Schedules")
                .font(typography.serif(19, relativeTo: .headline, weight: .semibold))
            HStack {
                Button {
                    Haptics.selection()
                    onClose()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 19, weight: .light))
                        .frame(width: 42, height: 42)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Close")
                Spacer()
                Button {
                    Haptics.selection()
                    onNew()
                } label: {
                    Image(systemName: "plus").font(.system(size: 19, weight: .light))
                        .frame(width: 42, height: 42)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("New schedule")
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    @ViewBuilder private var content: some View {
        if !schedules.isSupported {
            unsupportedState
        } else if case .failed(let message) = schedules.phase, schedules.schedules.isEmpty {
            failedState(message)
        } else if (schedules.phase == .idle || schedules.phase == .loading), schedules.schedules.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if schedules.schedules.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(schedules.schedules.enumerated()), id: \.element.id) { index, summary in
                    if index > 0 {
                        ClaudeDivider().padding(.leading, 20)
                    }
                    row(summary)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 18)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await schedules.load() }
    }

    private func row(_ summary: ScheduleSummary) -> some View {
        let state = summary.state(now: now, knownAgentIds: knownAgentIds)
        return Button {
            Haptics.selection()
            onOpen(summary.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(summary))
                        .font(typography.sans(15, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    Text(subtitle(summary))
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    ScheduleStatePill(state: state)
                    Text(nextCaption(summary, state: state))
                        .font(typography.sans(11))
                        .foregroundStyle(ClaudePalette.captionInk)
                }
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 58)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Schedule \(title(summary))")
    }

    private func title(_ summary: ScheduleSummary) -> String {
        if let name = summary.name, !name.isEmpty { return name }
        let firstLine = summary.prompt.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
        return firstLine.map(String.init) ?? "Untitled schedule"
    }

    private func subtitle(_ summary: ScheduleSummary) -> String {
        summary.cadence.words
    }

    private func nextCaption(_ summary: ScheduleSummary, state: ScheduleState) -> String {
        switch state {
        case .paused: return "Paused"
        case .expired, .finished: return "No upcoming run"
        default: return scheduleNextRun(summary.nextRunAt)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.system(size: 20, weight: .light))
                .frame(width: 48, height: 48)
                .background(ClaudePalette.panel, in: .circle)
            VStack(spacing: 4) {
                Text("No schedules yet").font(.system(size: 18))
                Text("Schedules run agents on a cadence.")
                    .font(.system(size: 16))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(ClaudePalette.secondary)
            Button {
                Haptics.selection()
                onNew()
            } label: {
                Label("New schedule", systemImage: "plus")
                    .font(typography.sans(16, weight: .medium))
                    .foregroundStyle(ClaudePalette.background)
                    .padding(.horizontal, 17)
                    .frame(height: 44)
                    .background(ClaudePalette.ink, in: .capsule)
            }
            .accessibilityIdentifier("schedules.new")
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(ClaudePalette.tertiaryInk)
            Text("Schedules aren't available on this host")
                .font(typography.sans(15, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
            Text("The daemon did not grant the automation.manage permission.")
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(ClaudePalette.tertiaryInk)
            Text(message)
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button {
                Haptics.selection()
                Task { await schedules.load() }
            } label: {
                Text("Retry")
                    .font(typography.sans(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                    .padding(.horizontal, 18)
                    .frame(height: 32)
                    .background(ClaudePalette.chip, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
}

private extension ScheduleCadence {
    /// The cadence line for display: "Every day at 9:00 · Europe/Sofia".
    var words: String {
        switch self {
        case .every(let everyMs): ScheduleWords.cadence(everyMs: everyMs)
        case .cron(let expression, let timezone): ScheduleWords.cadence(expression: expression, timezone: timezone)
        case .unknown(let raw): "Cron: \(raw)"
        }
    }
}

private extension ScheduleTarget {
    /// The stored new-agent config, when the target creates a fresh agent each run.
    var newAgentConfig: ScheduleNewAgentConfig? {
        if case .newAgent(let config) = self { return config }
        return nil
    }

    /// The agent id when the target prompts an existing agent (a heartbeat).
    var agentId: String? {
        switch self {
        case .agent(let agentId), .selfAgent(let agentId): agentId
        default: nil
        }
    }
}

// MARK: - Detail page

private struct ScheduleDetailPage: View {
    let session: HostSession
    let typography: ClaudeTypography
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
                .font(typography.serif(17, relativeTo: .headline, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: 200)
            HStack {
                Button {
                    Haptics.selection()
                    onBack()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 19, weight: .light))
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
                .font(typography.sans(15, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
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
                .font(.system(size: 19, weight: .light))
                .frame(width: 48, height: 48)
                .background(ClaudePalette.panel, in: .circle)
            Text(titleString(summary))
                .font(typography.serif(21, relativeTo: .headline, weight: .semibold))
                .foregroundStyle(ClaudePalette.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(summary.cadence.words)
                .font(typography.sans(14))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .multilineTextAlignment(.center)
            if let state, state != .active {
                ScheduleStatePill(state: state)
            } else {
                Text(scheduleNextRun(summary.nextRunAt))
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.captionInk)
            }
        }
        .padding(.vertical, 4)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(typography.sans(11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(ClaudePalette.secondaryInk)
            .padding(.leading, 6)
    }

    private func promptPanel(_ summary: ScheduleSummary) -> some View {
        Text(summary.prompt)
            .font(typography.sans(14))
            .foregroundStyle(ClaudePalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(ClaudePalette.panel, in: .rect(cornerRadius: 18))
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
                Text(title).font(typography.sans(15))
                Spacer(minLength: 8)
                Text(value)
                    .font(typography.sans(14))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let detail {
                Text(detail)
                    .font(typography.mono(11))
                    .foregroundStyle(ClaudePalette.captionInk)
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
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }

    private func runRow(_ run: ScheduleRun) -> some View {
        HStack(spacing: 10) {
            Group {
                switch run.status {
                case .succeeded:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(ClaudePalette.successInk)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(ClaudePalette.failureInk)
                case .running, .unknown:
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(scheduleTimestamp(run.startedAt))
                    .font(typography.sans(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                if let error = run.error, !error.isEmpty {
                    Text(error)
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .lineLimit(2)
                } else if let output = run.output, !output.isEmpty {
                    Text(output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? output)
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            Text(scheduleDuration(run.startedAt, run.endedAt))
                .font(typography.mono(11))
                .foregroundStyle(ClaudePalette.captionInk)
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
                .font(.system(size: 15, weight: .light))
                .frame(width: 22)
                .foregroundStyle(destructive ? ClaudePalette.failureInk : ClaudePalette.ink)
            Text(title)
                .font(typography.sans(15))
                .foregroundStyle(destructive ? ClaudePalette.failureInk : ClaudePalette.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(.rect)
    }
}

// MARK: - Editor page

private struct CadencePreset: Hashable {
    let label: String
    let expression: String

    static let all: [CadencePreset] = [
        .init(label: "Every day at 9:00", expression: "0 9 * * *"),
        .init(label: "Weekdays at 9:00", expression: "0 9 * * 1-5"),
        .init(label: "Mondays at 9:00", expression: "0 9 * * 1"),
        .init(label: "1st of the month at 9:00", expression: "0 9 1 * *"),
        .init(label: "Every 6 hours", expression: "0 */6 * * *"),
        .init(label: "Every hour", expression: "0 * * * *"),
    ]
}

private struct ScheduleEditorPage: View {
    let session: HostSession
    let typography: ClaudeTypography
    let seed: ClaudeSchedulesView.EditorSeed
    let onBack: () -> Void
    let onCreated: (String) -> Void
    let showToast: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The picker currently open inside the editor; nil shows the form.
    enum Picker: Hashable {
        case provider, model, mode, thinking, workspace
    }

    @State private var picker: Picker?
    @State private var isSaving = false

    @State private var name: String
    @State private var prompt: String
    @State private var cron: String
    @State private var usePreset: Int?
    @State private var timezone: String
    /// A cadence that is `.every` or otherwise not one we can edit as cron: shown read-only.
    @State private var readOnlyCadence: String?
    @State private var maxRuns: String
    @State private var cwd: String
    @State private var providerId: String
    @State private var modelId: String
    @State private var modeId: String
    @State private var thinkingId: String

    private var schedules: SchedulesStore { session.schedules }
    private var workspaces: [WorkspaceDescriptor] {
        session.workspaceDirectory.groups.flatMap(\.workspaces)
    }
    private var isHeartbeat: Bool { seed.isHeartbeat }
    private var catalog: AgentControlStore { session.agentControl }

    init(
        session: HostSession, typography: ClaudeTypography, seed: ClaudeSchedulesView.EditorSeed,
        onBack: @escaping () -> Void, onCreated: @escaping (String) -> Void, showToast: @escaping (String) -> Void
    ) {
        self.session = session
        self.typography = typography
        self.seed = seed
        self.onBack = onBack
        self.onCreated = onCreated
        self.showToast = showToast
        if let stored = seed.stored {
            _name = State(initialValue: stored.summary.name ?? "")
            _prompt = State(initialValue: stored.summary.prompt)
            _maxRuns = State(initialValue: stored.summary.maxRuns.map(String.init) ?? "")
            switch stored.summary.cadence {
            case .cron(let expression, let timezone):
                _cron = State(initialValue: expression)
                _timezone = State(initialValue: timezone ?? "")
                _usePreset = State(initialValue: CadencePreset.all.firstIndex(where: { $0.expression == expression }))
            default:
                _cron = State(initialValue: "")
                _timezone = State(initialValue: "")
                _usePreset = State(initialValue: nil)
                _readOnlyCadence = State(initialValue: stored.summary.cadence.words)
            }
            if let config = stored.summary.target.newAgentConfig {
                _cwd = State(initialValue: config.cwd)
                _providerId = State(initialValue: config.provider)
                _modelId = State(initialValue: config.model ?? "")
                _modeId = State(initialValue: config.modeId ?? "")
                _thinkingId = State(initialValue: config.thinkingOptionId ?? "")
            } else {
                _cwd = State(initialValue: "")
                _providerId = State(initialValue: "")
                _modelId = State(initialValue: "")
                _modeId = State(initialValue: "")
                _thinkingId = State(initialValue: "")
            }
        } else {
            let firstWorkspace = session.workspaceDirectory.groups.first?.workspaces.first
            _name = State(initialValue: "")
            _prompt = State(initialValue: "")
            _cron = State(initialValue: CadencePreset.all[0].expression)
            _usePreset = State(initialValue: 0)
            _timezone = State(initialValue: "")
            _readOnlyCadence = State(initialValue: nil)
            _maxRuns = State(initialValue: "")
            _cwd = State(initialValue: firstWorkspace?.cwd ?? "")
            let firstProvider = session.agentControl.readyProviders.first?.provider ?? ""
            _providerId = State(initialValue: firstProvider)
            _modelId = State(initialValue: "")
            _modeId = State(initialValue: "")
            _thinkingId = State(initialValue: "")
        }
    }

    var body: some View {
        Group {
            if let picker {
                pickerView(picker)
            } else {
                form
            }
        }
        .onAppear {
            if catalog.readyProviders.isEmpty {
                Task { await catalog.loadCatalog(cwd: nil) }
            }
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(seed.title)
                    .font(typography.serif(17, relativeTo: .headline, weight: .semibold))
                HStack {
                    Button {
                        Haptics.selection()
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 19, weight: .light))
                            .frame(width: 42, height: 42)
                    }
                    .glassEffect(in: .circle)
                    .accessibilityLabel("Back")
                    Spacer()
                }
            }
            .frame(height: 56)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fieldLabel("Name")
                    TextField("Optional", text: $name)
                        .font(typography.sans(15))
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .background(ClaudePalette.panel, in: .capsule)
                        .overlay { Capsule().stroke(ClaudePalette.ink.opacity(0.10), lineWidth: 0.5) }
                        .accessibilityIdentifier("schedule.name")
                    fieldLabel("Prompt")
                    ZStack(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("What should the agent do each time?")
                                .font(typography.sans(15))
                                .foregroundStyle(ClaudePalette.secondaryInk)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $prompt)
                            .font(typography.sans(15))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .accessibilityIdentifier("schedule.prompt")
                    }
                    .frame(height: 132)
                    .background(ClaudePalette.panel, in: .rect(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).stroke(ClaudePalette.ink.opacity(0.08), lineWidth: 0.5) }
                    cadenceSection
                    fieldLabel("Max runs")
                    TextField("Unlimited", text: $maxRuns)
                        .keyboardType(.numberPad)
                        .font(typography.sans(15))
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .background(ClaudePalette.panel, in: .capsule)
                        .overlay { Capsule().stroke(ClaudePalette.ink.opacity(0.10), lineWidth: 0.5) }
                        .accessibilityIdentifier("schedule.maxRuns")
                    if isHeartbeat {
                        Text("This schedule prompts an existing agent every run.")
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .padding(.horizontal, 6)
                    } else {
                        targetSection
                        agentSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            if let actionError = schedules.actionError {
                Text(actionError)
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            bottomBar
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(typography.sans(11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(ClaudePalette.secondaryInk)
            .padding(.leading, 6)
    }

    // MARK: Cadence

    private var cadenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Cadence")
            if let readOnlyCadence {
                HStack {
                    Image(systemName: "clock").foregroundStyle(ClaudePalette.secondaryInk)
                    Text(readOnlyCadence).font(typography.sans(15)).foregroundStyle(ClaudePalette.ink)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(ClaudePalette.panel, in: .capsule)
                .overlay { Capsule().stroke(ClaudePalette.ink.opacity(0.10), lineWidth: 0.5) }
                Text("Interval cadences can't be edited here yet.")
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .padding(.horizontal, 6)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(CadencePreset.all.enumerated()), id: \.offset) { index, preset in
                        let selected = usePreset == index && cron == preset.expression
                        Button {
                            Haptics.selection()
                            usePreset = index
                            cron = preset.expression
                        } label: {
                            Text(preset.label)
                                .font(typography.sans(12, weight: .medium))
                                .foregroundStyle(selected ? ClaudePalette.background : ClaudePalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(selected ? ClaudePalette.ink : ClaudePalette.panel, in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                TextField("Custom cron expression", text: $cron)
                    .font(typography.mono(14))
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(ClaudePalette.panel, in: .capsule)
                    .overlay {
                        Capsule().stroke(
                            cronIsInvalid && !cron.isEmpty
                                ? ClaudePalette.failureInk
                                : ClaudePalette.ink.opacity(0.10),
                            lineWidth: 0.5)
                    }
                    .onChange(of: cron) { _, expression in
                        if let index = CadencePreset.all.firstIndex(where: { $0.expression == expression }) {
                            usePreset = index
                        } else {
                            usePreset = nil
                        }
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("schedule.cron")
                if cronIsInvalid && !cron.isEmpty {
                    Text("Five fields: minute hour day-of-month month day-of-week.")
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .padding(.horizontal, 6)
                }
                TextField("Timezone (optional)", text: $timezone)
                    .font(typography.mono(14))
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(ClaudePalette.panel, in: .capsule)
                    .overlay { Capsule().stroke(ClaudePalette.ink.opacity(0.10), lineWidth: 0.5) }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("schedule.timezone")
            }
        }
    }

    // MARK: Target

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Target workspace")
            RowGroup {
                ForEach(Array(workspaces.enumerated()), id: \.element.id) { index, workspace in
                    if index > 0 { RowDivider() }
                    workspaceRow(workspace)
                }
                if !cwd.isEmpty, !workspaces.contains(where: { $0.cwd == cwd }) {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom directory").font(typography.sans(15))
                        Text(cwd)
                            .font(typography.mono(11))
                            .foregroundStyle(ClaudePalette.captionInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func workspaceRow(_ workspace: WorkspaceDescriptor) -> some View {
        let selected = cwd == workspace.cwd
        return Button {
            Haptics.selection()
            cwd = workspace.cwd
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.title ?? workspace.name)
                        .font(typography.sans(15))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    Text("\(workspace.projectDisplayName)\(workspace.branch.map { " · \($0)" } ?? "")")
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ClaudePalette.ink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Agent

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Agent")
            RowGroup {
                SheetRow(title: "Provider", value: providerValue, chevron: true) {
                    picker = .provider
                }
                RowDivider()
                SheetRow(title: "Model", value: modelValue, chevron: true) {
                    picker = .model
                }
                RowDivider()
                SheetRow(title: "Mode", value: modeValue, chevron: true) {
                    picker = .mode
                }
                RowDivider()
                SheetRow(title: "Thinking", value: thinkingValue, chevron: true) {
                    picker = .thinking
                }
            }
        }
    }

    private var providerValue: String {
        if providerId.isEmpty { return "Choose a provider" }
        return catalog.provider(providerId)?.label ?? providerId
    }

    private var modelValue: String {
        if modelId.isEmpty { return "Provider default" }
        if let match = catalog.models(forProvider: providerId).first(where: { $0.id == modelId }) {
            return match.label
        }
        return modelId
    }

    private var modeValue: String {
        if modeId.isEmpty { return "Provider default" }
        return catalog.modes(forProvider: providerId).first(where: { $0.id == modeId })?.label ?? modeId
    }

    private var thinkingValue: String {
        if thinkingId.isEmpty { return "Provider default" }
        let modelId = resolvedThinkingModelId
        guard let modelId else { return thinkingId }
        return catalog.thinkingOptions(forProvider: providerId, modelId: modelId)
            .first(where: { $0.id == thinkingId })?.label ?? thinkingId
    }

    private var resolvedThinkingModelId: String? {
        if !modelId.isEmpty { return modelId }
        return catalog.defaultModel(forProvider: providerId)?.id
    }

    // MARK: Bottom bar and validation

    private var promptIsEmpty: Bool { prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var cronIsInvalid: Bool { !ScheduleWords.isValid(cron: cron) }
    private var maxRunsIsInvalid: Bool {
        let trimmed = maxRuns.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return Int(trimmed).map { $0 >= 1 } != true
    }
    private var canSave: Bool {
        if isHeartbeat {
            return !promptIsEmpty && !maxRunsIsInvalid && (readOnlyCadence != nil || !cronIsInvalid)
        }
        return !promptIsEmpty && !cronIsInvalid && !maxRunsIsInvalid && !providerId.isEmpty && !cwd.isEmpty
    }

    private var bottomBar: some View {
        Button {
            save()
        } label: {
            Text(isSaving ? "Saving…" : (seed.stored == nil ? "Create schedule" : "Save changes"))
                .font(typography.sans(15, weight: .semibold))
                .foregroundStyle(canSave ? ClaudePalette.background : ClaudePalette.background.opacity(0.55))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(canSave ? ClaudePalette.ink : ClaudePalette.ink.opacity(0.3), in: .capsule)
        }
        .disabled(!canSave || isSaving)
        .accessibilityIdentifier("schedule.save")
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func save() {
        Haptics.selection()
        isSaving = true
        if let stored = seed.stored {
            Task {
                let edits = buildEdits(stored)
                if await schedules.update(stored.id, edits) {
                    showToast("Saved")
                    onCreated(stored.id)
                }
                isSaving = false
            }
        } else {
            Task {
                let config = ScheduleNewAgentConfig(
                    provider: providerId, cwd: cwd,
                    modeId: modeId.isEmpty ? nil : modeId,
                    model: modelId.isEmpty ? nil : modelId,
                    thinkingOptionId: thinkingId.isEmpty ? nil : thinkingId)
                let trimmedTimezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)
                let cadence = ScheduleCadence.cron(
                    expression: cron.trimmingCharacters(in: .whitespacesAndNewlines),
                    timezone: trimmedTimezone.isEmpty ? nil : trimmedTimezone)
                let maxRunsValue = Int(maxRuns.trimmingCharacters(in: .whitespacesAndNewlines))
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let draft = ScheduleDraft(
                    name: trimmedName.isEmpty ? nil : trimmedName,
                    prompt: prompt, cadence: cadence, target: .newAgent(config), maxRuns: maxRunsValue)
                if let created = await schedules.create(draft) {
                    showToast("Schedule created")
                    onCreated(created.id)
                }
                isSaving = false
            }
        }
    }

    private func buildEdits(_ stored: StoredSchedule) -> ScheduleEdits {
        let initial = stored.summary
        let namePatch = patchString(name, comparedTo: initial.name ?? "")
        let promptEdit = prompt.trimmingCharacters(in: .whitespacesAndNewlines) == initial.prompt.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : prompt
        let maxRunsPatch = patchInt(maxRuns, comparedTo: initial.maxRuns)

        var cadenceEdit: ScheduleCadence?
        if readOnlyCadence == nil {
            let trimmedTimezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)
            let cadence = ScheduleCadence.cron(
                expression: cron.trimmingCharacters(in: .whitespacesAndNewlines),
                timezone: trimmedTimezone.isEmpty ? nil : trimmedTimezone)
            if cadence != initial.cadence { cadenceEdit = cadence }
        }

        guard let config = initial.target.newAgentConfig else {
            // A heartbeat: provider/model/mode/thinking stay untouched.
            return ScheduleEdits(name: namePatch, prompt: promptEdit, cadence: cadenceEdit, maxRuns: maxRunsPatch)
        }

        var newAgentConfig: ScheduleNewAgentConfigUpdate? = nil
        let providerChanged = providerId != config.provider
        let modelPatch = patchString(modelId, comparedTo: config.model ?? "")
        let modePatch = patchString(modeId, comparedTo: config.modeId ?? "")
        let thinkingPatch = patchString(thinkingId, comparedTo: config.thinkingOptionId ?? "")
        if providerChanged || modelPatch != .unchanged || modePatch != .unchanged || thinkingPatch != .unchanged {
            newAgentConfig = ScheduleNewAgentConfigUpdate(
                provider: providerChanged ? providerId : nil,
                model: modelPatch, modeId: modePatch, thinkingOptionId: thinkingPatch)
        }

        return ScheduleEdits(
            name: namePatch, prompt: promptEdit, cadence: cadenceEdit,
            maxRuns: maxRunsPatch, newAgentConfig: newAgentConfig)
    }

    private func patchString(_ new: String, comparedTo old: String) -> SchedulePatch<String> {
        let newTrimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldTrimmed = old.trimmingCharacters(in: .whitespacesAndNewlines)
        if newTrimmed == oldTrimmed { return .unchanged }
        return newTrimmed.isEmpty ? .clear : .set(newTrimmed)
    }

    private func patchInt(_ new: String, comparedTo old: Int?) -> SchedulePatch<Int> {
        let newTrimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = newTrimmed.isEmpty ? nil : Int(newTrimmed)
        guard newTrimmed.isEmpty || parsed != nil else { return .unchanged } // invalid input can't be saved anyway
        if parsed == old { return .unchanged }
        guard let parsed else { return .clear }
        return .set(parsed)
    }
}

// MARK: - Pickers

extension ScheduleEditorPage {
    /// Every picker page: a back row and a list of rows. One shape for provider/model/mode/thinking/workspace.
    @ViewBuilder fileprivate func pickerView(_ which: Picker) -> some View {
        switch which {
        case .provider: providerPicker
        case .model: modelPicker
        case .mode: modePicker
        case .thinking: thinkingPicker
        case .workspace: workspacePicker
        }
    }

    fileprivate func pickerShell<Content: View>(
        title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(typography.serif(17, relativeTo: .headline, weight: .semibold))
                HStack {
                    Button {
                        Haptics.selection()
                        picker = nil
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 19, weight: .light))
                            .frame(width: 42, height: 42)
                    }
                    .glassEffect(in: .circle)
                    .accessibilityLabel("Back")
                    Spacer()
                }
            }
            .frame(height: 56)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            content()
        }
    }

    fileprivate func pickerRow(
        title: String, detail: String? = nil, checked: Bool, badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(typography.sans(15))
                        if let badge {
                            Text(badge)
                                .font(typography.sans(10, weight: .semibold))
                                .foregroundStyle(ClaudePalette.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(ClaudePalette.ink.opacity(0.06), in: .capsule)
                        }
                    }
                    if let detail {
                        Text(detail)
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ClaudePalette.ink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    fileprivate var providerPicker: some View {
        pickerShell(title: "Provider") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if catalog.readyProviders.isEmpty {
                        Text("No providers are ready on this host.")
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .padding(16)
                    } else {
                        RowGroup {
                            ForEach(Array(catalog.readyProviders.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { RowDivider() }
                                pickerRow(
                                    title: entry.label ?? entry.provider,
                                    detail: entry.description,
                                    checked: providerId == entry.provider
                                ) {
                                    providerId = entry.provider
                                    modelId = ""
                                    modeId = ""
                                    thinkingId = ""
                                    picker = nil
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                }
            }
            .onAppear {
                Task { await catalog.loadCatalog(cwd: nil) }
            }
        }
    }

    fileprivate var modelPicker: some View {
        pickerShell(title: "Model") {
            let models = catalog.models(forProvider: providerId)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    RowGroup {
                        pickerRow(title: "Provider default", checked: modelId.isEmpty) {
                            modelId = ""
                            picker = nil
                        }
                        ForEach(Array(models.enumerated()), id: \.element.id) { _, model in
                            RowDivider()
                            pickerRow(
                                title: model.label,
                                detail: model.description,
                                checked: modelId == model.id,
                                badge: model.isDefault == true ? "Default" : nil
                            ) {
                                modelId = model.id
                                thinkingId = ""
                                picker = nil
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    if models.isEmpty {
                        Text(providerId.isEmpty ? "Choose a provider first." : "This provider reports no models.")
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .padding(16)
                    }
                }
            }
        }
    }

    fileprivate var modePicker: some View {
        pickerShell(title: "Mode") {
            let modes = catalog.modes(forProvider: providerId)
            ScrollView {
                RowGroup {
                    pickerRow(title: "Provider default", checked: modeId.isEmpty) {
                        modeId = ""
                        picker = nil
                    }
                    ForEach(Array(modes.enumerated()), id: \.element.id) { _, mode in
                        RowDivider()
                        pickerRow(title: mode.label, detail: mode.description, checked: modeId == mode.id) {
                            modeId = mode.id
                            picker = nil
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
    }

    fileprivate var thinkingPicker: some View {
        pickerShell(title: "Thinking") {
            let options: [ProviderThinkingOption] = {
                guard let modelId = resolvedThinkingModelId else { return [] }
                return catalog.thinkingOptions(forProvider: providerId, modelId: modelId)
            }()
            ScrollView {
                RowGroup {
                    pickerRow(title: "Provider default", checked: thinkingId.isEmpty) {
                        thinkingId = ""
                        picker = nil
                    }
                    ForEach(Array(options.enumerated()), id: \.element.id) { _, option in
                        RowDivider()
                        pickerRow(
                            title: option.label,
                            detail: option.description,
                            checked: thinkingId == option.id,
                            badge: option.isDefault == true ? "Default" : nil
                        ) {
                            thinkingId = option.id
                            picker = nil
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                if options.isEmpty {
                    Text(resolvedThinkingModelId == nil
                        ? "Choose a provider first."
                        : "This model reports no thinking levels.")
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .padding(16)
                }
            }
        }
    }

    fileprivate var workspacePicker: some View {
        pickerShell(title: "Target workspace") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    RowGroup {
                        ForEach(Array(workspaces.enumerated()), id: \.element.id) { index, workspace in
                            if index > 0 { RowDivider() }
                            pickerRow(
                                title: workspace.title ?? workspace.name,
                                detail: "\(workspace.projectDisplayName)\(workspace.branch.map { " · \($0)" } ?? "")",
                                checked: cwd == workspace.cwd
                            ) {
                                cwd = workspace.cwd
                                picker = nil
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    if workspaces.isEmpty {
                        Text("This host has no workspaces yet. Create one from the sidebar first.")
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .padding(16)
                    }
                }
            }
        }
    }
}

#endif
