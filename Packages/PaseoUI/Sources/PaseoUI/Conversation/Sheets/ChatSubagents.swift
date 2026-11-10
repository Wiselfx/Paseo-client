#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// M7f — the subagents track: a quiet pill under the header (provider subagents) and a sheet
/// that lists them with status; rows open the read-only timeline.

/// Counts the pill reports: the ticket's wording is `N subagents`, `N working`, `N failed`.
/// Provider rows carry no attention/needs-input signal, so there is no "needs input" mark here.
/// Managed rows are ordinary agents (`session.subagents(of:)`), so they do carry status.
struct SubagentTrackPill: View {
    let items: [ProviderSubagent]
    /// Paseo-managed child agents: ordinary agents labelled with this parent's id.
    var managed: [AgentSnapshot] = []
    let action: () -> Void


    var running: Int {
        items.filter { $0.status == .running }.count + managed.filter { $0.status == .running }.count
    }
    var failed: Int {
        items.filter { $0.status == .failed }.count + managed.filter { $0.status == .error }.count
    }
    var total: Int { items.count + managed.count }

    var text: String {
        var parts: [String] = []
        if running > 0 { parts.append("\(running) working") }
        if failed > 0 { parts.append("\(failed) failed") }
        if parts.isEmpty {
            return total == 1 ? "1 subagent" : "\(total) subagents"
        }
        return parts.joined(separator: " · ")
    }

    var accessibilityText: String {
        var parts: [String] = []
        if running > 0 { parts.append("\(running) working") }
        if failed > 0 { parts.append("\(failed) failed") }
        if parts.isEmpty { parts.append(total == 1 ? "1 subagent" : "\(total) subagents") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "person.2")
                    .font(.glyph(.small, weight: .medium))
                Text(text)
                    .font(.paseo(.footnote))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .foregroundStyle(failed > 0 ? Palette.failureInk : Palette.secondaryInk)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Palette.chip, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transcript.subagents")
        .accessibilityLabel("Subagents: \(accessibilityText)")
    }
}

/// Provider subagent status: dot color and sentence-case label.
enum SubagentStatusWord {
    static func label(_ status: ProviderSubagent.Status) -> String {
        switch status {
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .canceled: "Canceled"
        case .unknown: "Unknown"
        }
    }

    static func dot(_ status: ProviderSubagent.Status) -> Color {
        switch status {
        case .running: Palette.orange
        case .completed: Palette.successInk
        case .failed: Palette.failureInk
        case .canceled, .unknown: Palette.tertiaryInk
        }
    }
}

/// The sheet that lists subagents. Managed rows (ordinary agents labelled with this parent,
/// `session.subagents(of:)`) open their conversation and can be detached; provider rows are
/// read-only and open a timeline. "Archive finished" hides every non-running provider row for
/// this session (app-side only, in memory — provider rows die with the provider session).
struct ChatSubagentsSheet: View {
    let session: HostSession
    let parentAgentId: String
    let subagents: ConversationSubagents
    @Binding var hiddenIds: Set<String>
    /// Opens a managed subagent in the shell; the caller dismisses the sheet.
    var onOpenAgent: (String) -> Void

    @State private var pushTarget: ProviderSubagent?
    @State private var detachTarget: AgentSnapshot?
    @State private var detachingId: String?
    @State private var detachError: String?

    /// Upstream `resolveSubagentLabel` (`subagents/detach-subagent.ts`): a blank title, or the
    /// "new agent" placeholder, names nothing, so the dialog says "This subagent".
    static func detachLabel(_ agent: AgentSnapshot) -> String {
        let trimmed = agent.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.lowercased() != "new agent" else {
            return "This subagent"
        }
        return trimmed
    }

    private var items: [ProviderSubagent] {
        subagents.items.filter { !hiddenIds.contains($0.id) }
    }

    /// Paseo-managed child agents, oldest first like upstream's track (`select.ts` sorts by
    /// `createdAt`); they are ordinary agents, so they never appear in `subagents.items`.
    private var managed: [AgentSnapshot] {
        session.subagents(of: parentAgentId)
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// Upstream gates Detach on `features.agentDetach` (`panels/agent-tracks.tsx:67`).
    private var canDetach: Bool {
        session.serverInfo?.hasFeature("agentDetach") == true
    }

    private var finishedCount: Int {
        items.filter { $0.status != .running }.count
    }

    var body: some View {
        SheetScaffold("Subagents", detents: .mediumLarge) {
            Group {
                if subagents.isLoading && items.isEmpty {
                    LoadingState()
                } else if items.isEmpty && managed.isEmpty {
                    EmptyState(
                        systemImage: "person.2",
                        title: "No subagents",
                        message: "Subagents your provider runs for this agent appear here."
                    )
                    .padding(.horizontal, 40)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(managed) { agent in
                                managedRow(agent)
                                if agent.id != managed.last?.id || !items.isEmpty {
                                    ClaudeDivider().padding(.leading, 44)
                                }
                            }
                            ForEach(items) { item in
                                subagentRow(item)
                                if item.id != items.last?.id {
                                    ClaudeDivider().padding(.leading, 44)
                                }
                            }
                            if let error = detachError ?? subagents.error {
                                InlineBanner(.failure, title: error)
                                    .padding(.horizontal, Space.lg)
                                    .padding(.vertical, 10)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if finishedCount > 0 {
                    VStack(spacing: 0) {
                        ClaudeDivider()
                        Button("Hide finished") {
                            hiddenIds.formUnion(items.filter { $0.status != .running }.map(\.id))
                        }
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(.rect)
                    }
                    .background(Palette.panel)
                }
            }
            .navigationDestination(item: $pushTarget) { subagent in
                ChatSubagentTimelineView(
                    subagents: subagents, subagent: subagent)
            }
            .confirmationDialog(
                "Detach subagent?",
                isPresented: Binding(
                    get: { detachTarget != nil },
                    set: { if !$0 { detachTarget = nil } }),
                titleVisibility: .visible,
                presenting: detachTarget
            ) { agent in
                // Upstream's confirm is not destructive: detaching loses nothing.
                Button("Detach") {
                    detachTarget = nil
                    Task { await detach(agent) }
                }
                Button("Cancel", role: .cancel) { detachTarget = nil }
            } message: { agent in
                Text(
                    "\(Self.detachLabel(agent)) will leave this track and continue as a standalone agent."
                )
            }
            .task { await subagents.load() }
        }
    }

    private func subagentRow(_ item: ProviderSubagent) -> some View {
        Button {
            pushTarget = item
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(SubagentStatusWord.dot(item.status))
                    .frame(width: 8, height: 8)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rowTitle(item))
                        .font(.paseo(.callout, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let subtitle = rowSubtitle(item) {
                        Text(subtitle)
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(SubagentStatusWord.label(item.status))
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rowTitle(item)), \(SubagentStatusWord.label(item.status))")
    }

    /// A managed subagent: ordinary agent row plus the detach action. Upstream shows the action
    /// cluster always on compact form factors (a phone) and on hover on desktop
    /// (`subagents-track.tsx`, `actionsAlwaysVisible`), so the button is visible here; the context
    /// menu carries the same action for a long press.
    private func managedRow(_ agent: AgentSnapshot) -> some View {
        HStack(spacing: 12) {
            StatusDot(managedStatus(agent))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(managedTitle(agent))
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(providerLabel(agent))
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if canDetach {
                if detachingId == agent.id {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("Detaching")
                } else {
                    Button {
                        detachTarget = agent
                    } label: {
                        Image(systemName: "person.badge.minus")
                            .font(.glyph(.regular, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(width: 28, height: 28)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Detach \(managedTitle(agent))")
                    .accessibilityIdentifier("subagents.detach")
                }
            }
            Image(systemName: "chevron.right")
                .font(.glyph(.small, weight: .semibold))
                .foregroundStyle(Palette.tertiaryInk)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .contentShape(.rect)
        .onTapGesture {
            onOpenAgent(agent.id)
        }
        .contextMenu {
            Button("Open agent", systemImage: "arrow.up.right.square") {
                onOpenAgent(agent.id)
            }
            if canDetach {
                Button("Detach", systemImage: "person.badge.minus") {
                    detachTarget = agent
                }
            }
        }
    }

    private func managedTitle(_ agent: AgentSnapshot) -> String {
        let trimmed = agent.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "New agent" : trimmed
    }

    private func providerLabel(_ agent: AgentSnapshot) -> String {
        session.agentControl.provider(agent.provider)?.label ?? agent.provider
    }

    /// The same dot the panel's agent rows use: attention first, then the lifecycle status.
    private func managedStatus(_ agent: AgentSnapshot) -> StatusDot.State {
        switch agent.attention {
        case .permission: return .attention
        case .error: return .failed
        case .finished: return .unread
        case .unknown, nil: break
        }
        return switch agent.status {
        case .running: .running
        case .error: .failed
        case .initializing, .idle, .closed, .unknown: .idle
        }
    }

    /// Detach, then open the agent: upstream's `requestDetachSubagent` opens the detached agent
    /// and reports a failure through the toast. Here the failure lands in the sheet's error line.
    private func detach(_ agent: AgentSnapshot) async {
        detachingId = agent.id
        detachError = nil
        let detached = await session.agentLifecycle.detach(agentId: agent.id)
        detachingId = nil
        guard detached else {
            detachError = session.agentLifecycle.actionError ?? "The detach failed."
            return
        }
        // The label is gone on the daemon; refresh so the row leaves this list and the agent
        // list stops nesting it.
        await session.refreshAgents()
        Haptics.success()
        onOpenAgent(agent.id)
    }

    private func rowTitle(_ item: ProviderSubagent) -> String {
        item.title ?? item.description ?? item.provider
    }

    private func rowSubtitle(_ item: ProviderSubagent) -> String? {
        if item.title != nil {
            return item.description ?? item.subtitle
        }
        return item.subtitle
    }
}

/// One provider subagent's timeline, read-only: the tail page, plain rows.
struct ChatSubagentTimelineView: View {
    let subagents: ConversationSubagents
    let subagent: ProviderSubagent

    @State private var rows: [ProviderSubagentTimelineRequest.Response.Row] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if loading && rows.isEmpty {
                    LoadingState()
                        .padding(.top, 60)
                } else if let error {
                    VStack(spacing: Space.md) {
                        InlineBanner(
                            .failure, title: error,
                            action: ("Try again", { Task { await load() } }))
                    }
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity)
                } else if rows.isEmpty {
                    EmptyState(title: "No timeline rows yet.")
                        .padding(.top, 60)
                } else {
                    ForEach(rows, id: \.seq) { row in
                        timelineRow(row)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Palette.background)
        .navigationTitle(rowTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var rowTitle: String {
        subagent.title ?? subagent.description ?? subagent.provider
    }

    private func load() async {
        loading = true
        if let page = await subagents.timelinePage(for: subagent.id, limit: 50) {
            rows = page.rows
            error = nil
        } else {
            error = subagents.error ?? "Couldn't load the timeline."
        }
        loading = false
    }

    @ViewBuilder
    private func timelineRow(_ row: ProviderSubagentTimelineRequest.Response.Row) -> some View {
        switch row.item {
        case .userMessage(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text("TASK")
                    .font(.paseo(.caption2, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.tertiaryInk)
                Text(message.text)
                    .font(.paseo(.processTitle))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .assistantMessage(let message):
            Text(message.text)
                .font(.paseo(.processTitle))
                .foregroundStyle(Palette.ink)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        case .reasoning(let reasoning):
            Text(reasoning.text.replacingOccurrences(of: "\n", with: " "))
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.tertiaryInk)
                .lineLimit(2)
        case .toolCall(let call):
            ToolCallLine(call: call)
        case .todo(let list):
            Text("Todo · \(PaseoFormat.integer(list.items.count)) item\(list.items.count == 1 ? "" : "s")")
                .font(.paseo(.codeSmall))
                .foregroundStyle(Palette.tertiaryInk)
        case .error(let message):
            Text(message)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.failureInk)
        case .notification(let level, let message):
            Text("\(level) · \(message)")
                .font(.paseo(.caption))
                .foregroundStyle(Palette.tertiaryInk)
        case .compaction:
            Text("Compacted")
                .font(.paseo(.caption))
                .foregroundStyle(Palette.tertiaryInk)
        case .unknown:
            Text("Unknown item")
                .font(.paseo(.caption))
                .foregroundStyle(Palette.tertiaryInk)
        }
    }
}

/// A one-line `verb · argument` for a tool call, e.g. `Read · src/server.ts`.
private struct ToolCallLine: View {
    let call: ToolCall

    private var presentation: ToolCallPresentation { ToolCallPresentation(call) }

    var body: some View {
        HStack(spacing: 8) {
            Text(presentation.title)
                .font(.paseo(.codeSmall))
                .foregroundStyle(Palette.tertiaryInk)
            if let subtitle = presentation.subtitle {
                Text(subtitle)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
