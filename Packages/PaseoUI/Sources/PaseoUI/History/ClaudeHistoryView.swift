#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The History screen (M7 §3): every agent on this host — live and archived — newest first,
/// grouped by day (Today / Yesterday / Earlier), with a title filter.
///
/// Rows show an "Archived" badge for archived agents. Tapping an archived row unarchives it and
/// opens the agent; a live row opens it directly. Swipe or long-press a row for actions:
/// Rename, Archive (confirmation when the agent is running), Delete permanently (destructive),
/// Copy agent ID.
struct ClaudeHistoryView: View {
    let session: HostSession
    let onClose: () -> Void
    /// Tap row → the sidebar dismisses this sheet and selects the agent.
    let onOpenAgent: (String) -> Void

    @State private var query = ""
    @State private var renamingAgent: AgentSnapshot?
    @State private var renameText = ""
    @State private var agentPendingArchive: AgentSnapshot?
    @State private var agentPendingDelete: AgentSnapshot?
    @State private var dismissedActionError: String?

    private var agents: [AgentSnapshot] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = session.agentLifecycle.entries
        guard !trimmed.isEmpty else { return matches }
        return matches.filter { title(for: $0).lowercased().contains(trimmed) }
    }

    private var groups: [HistoryGroup] {
        let calendar = Calendar.current
        var today: [AgentSnapshot] = [], yesterday: [AgentSnapshot] = [], earlier: [AgentSnapshot] = []
        for agent in agents {
            let reference = Date(timeIntervalSince1970: 0)
            let date = PaseoDate.parse(agent.lastUserMessageAt ?? agent.updatedAt) ?? reference
            if calendar.isDateInToday(date) {
                today.append(agent)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(agent)
            } else {
                earlier.append(agent)
            }
        }
        return [
            HistoryGroup(label: "Today", agents: today),
            HistoryGroup(label: "Yesterday", agents: yesterday),
            HistoryGroup(label: "Earlier", agents: earlier),
        ].filter { !$0.agents.isEmpty }
    }

    /// Error from the store that hasn't been dismissed yet.
    private var visibleActionError: String? {
        let error = session.agentLifecycle.actionError
        guard let error, error != dismissedActionError else { return nil }
        return error
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            if let visibleActionError {
                actionErrorBanner(visibleActionError)
            }
            content
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task {
            if session.agentLifecycle.phase == .idle {
                await session.agentLifecycle.load()
            }
        }
        .alert(
            "Rename agent",
            isPresented: Binding(
                get: { renamingAgent != nil },
                set: { if !$0 { renamingAgent = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingAgent = nil }
            Button("Rename") {
                guard let agent = renamingAgent else { return }
                let next = renameText
                renamingAgent = nil
                Task { await session.agentLifecycle.rename(agentId: agent.id, to: next) }
            }
        } message: {
            Text("Choose a short name for this agent.")
        }
        .confirmationDialog(
            "Archive agent?",
            isPresented: Binding(
                get: { agentPendingArchive != nil },
                set: { if !$0 { agentPendingArchive = nil } }),
            titleVisibility: .visible
        ) {
            Button("Archive") {
                guard let agent = agentPendingArchive else { return }
                agentPendingArchive = nil
                Task {
                    let archived = await session.agentLifecycle.archive(agentId: agent.id)
                    if archived { await session.refreshAgents() }
                }
            }
            Button("Cancel", role: .cancel) { agentPendingArchive = nil }
        } message: {
            Text("This agent is still running. Archiving it will stop the agent.")
        }
        .confirmationDialog(
            "Delete agent?",
            isPresented: Binding(
                get: { agentPendingDelete != nil },
                set: { if !$0 { agentPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) {
                guard let agent = agentPendingDelete else { return }
                agentPendingDelete = nil
                Task {
                    let deleted = await session.agentLifecycle.delete(agentId: agent.id)
                    if deleted { await session.refreshAgents() }
                }
            }
            Button("Cancel", role: .cancel) { agentPendingDelete = nil }
        } message: {
            Text("This removes its history for good.")
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("History")
                .font(.paseo(.title, weight: .semibold))
            HStack {
                Button {
                    Haptics.selection()
                    onClose()
                } label: {
                    Image(systemName: "xmark").font(.glyph(.large, weight: .light))
                        .frame(width: 42, height: 42)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(.small))
                .foregroundStyle(Palette.secondaryInk)
            TextField("Search history", text: $query)
                .font(.paseo(.callout))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("history.search")
            if !query.isEmpty {
                Button {
                    Haptics.selection()
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.glyph(.small))
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(Palette.chip, in: .rect(cornerRadius: Radius.md))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func actionErrorBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Palette.failureInk)
            Text(message)
                .font(.paseo(.caption))
                .foregroundStyle(Palette.failureInk)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                dismissedActionError = message
            } label: {
                Image(systemName: "xmark")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.failureInk)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.failureInk.opacity(0.08))
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch session.agentLifecycle.phase {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Loading history…")
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle")
                    .font(.glyph(.xlarge, weight: .light))
                    .foregroundStyle(Palette.failureInk)
                Text("Couldn't load agent history")
                    .font(.paseo(.callout, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(message)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    Task { await session.agentLifecycle.load() }
                } label: {
                    Text("Retry")
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Palette.chip, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if agents.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.glyph(.xlarge, weight: .light))
                .foregroundStyle(Palette.tertiaryInk)
            Text(query.isEmpty ? "No sessions yet" : "No sessions match")
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text(query.isEmpty ? "Start one from the sidebar." : "Try a different title.")
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private var list: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.agents) { agent in
                        row(agent)
                    }
                } header: {
                    Text(group.label.uppercased())
                        .font(.paseo(.caption2, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            if session.agentLifecycle.hasMore {
                Button {
                    Task { await session.agentLifecycle.loadMore() }
                } label: {
                    HStack {
                        Spacer()
                        if session.agentLifecycle.isLoadingMore {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Load more")
                                .font(.paseo(.callout, weight: .medium))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        Spacer()
                    }
                    .frame(height: 44)
                }
                .accessibilityLabel("Load more")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .textCase(nil)
    }

    private func row(_ agent: AgentSnapshot) -> some View {
        let archived = agent.archivedAt != nil
        return Button {
            Haptics.selection()
            if archived {
                Task {
                    let unarchived = await session.agentLifecycle.unarchive(agentId: agent.id)
                    if unarchived {
                        await session.refreshAgents()
                        onOpenAgent(agent.id)
                    }
                }
            } else {
                onOpenAgent(agent.id)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title(for: agent))
                            .font(.paseo(.callout, weight: .medium))
                            .foregroundStyle(archived ? Palette.secondaryInk : Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if archived {
                            Text("Archived")
                                .font(.paseo(.caption2, weight: .semibold))
                                .foregroundStyle(Palette.tertiaryInk)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.chip, in: .capsule)
                        }
                    }
                    Text(subtitle(for: agent))
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(relativeAge(agent.lastUserMessageAt ?? agent.updatedAt))
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.captionInk)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowSeparatorTint(Palette.divider)
        .accessibilityLabel("\(archived ? "Archived agent" : "Open agent") \(title(for: agent))")
        .contextMenu { rowActions(agent) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { agentPendingDelete = agent } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { requestArchive(agent) } label: {
                Label(archived ? "Unarchive" : "Archive", systemImage: archived ? "tray.and.arrow.up" : "archivebox")
            }
            .tint(Palette.secondaryInk)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { beginRename(agent) } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(Palette.secondaryInk)
        }
    }

    @ViewBuilder private func rowActions(_ agent: AgentSnapshot) -> some View {
        Button { beginRename(agent) } label: {
            Label("Rename", systemImage: "pencil")
        }
        if agent.archivedAt == nil {
            Button { requestArchive(agent) } label: {
                Label("Archive", systemImage: "archivebox")
            }
        } else {
            Button {
                Task {
                    let unarchived = await session.agentLifecycle.unarchive(agentId: agent.id)
                    if unarchived { await session.refreshAgents() }
                }
            } label: {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            }
        }
        Button {
            UIPasteboard.general.string = agent.id
            Haptics.selection()
        } label: {
            Label("Copy agent ID", systemImage: "doc.on.doc")
        }
        Button(role: .destructive) {
            agentPendingDelete = agent
        } label: {
            Label("Delete permanently", systemImage: "trash")
        }
    }

    // MARK: Row actions

    private func beginRename(_ agent: AgentSnapshot) {
        renameText = title(for: agent)
        renamingAgent = agent
    }

    private func requestArchive(_ agent: AgentSnapshot) {
        if agent.archivedAt != nil {
            Task {
                let unarchived = await session.agentLifecycle.unarchive(agentId: agent.id)
                if unarchived { await session.refreshAgents() }
            }
            return
        }
        if agent.status == .running {
            agentPendingArchive = agent
            return
        }
        Task {
            let archived = await session.agentLifecycle.archive(agentId: agent.id)
            if archived { await session.refreshAgents() }
        }
    }

    private func title(for agent: AgentSnapshot) -> String {
        let title = agent.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false ? title : nil) ?? "New agent"
    }

    /// `workspace · provider · model`, middle-truncated.
    private func subtitle(for agent: AgentSnapshot) -> String {
        var parts: [String] = []
        if let workspaceId = agent.workspaceId,
           let workspace = session.workspaceDirectory.groups.flatMap(\.workspaces)
           .first(where: { $0.id == workspaceId }) {
            parts.append(workspace.title?.isEmpty == false ? workspace.title! : workspace.name)
        }
        parts.append(session.agentControl.provider(agent.provider)?.label ?? agent.provider)
        if let model = agent.model {
            let label = session.agentControl.models(forProvider: agent.provider)
                .first(where: { $0.id == model })?.label
            parts.append(label ?? model)
        }
        return parts.joined(separator: " · ")
    }

    private func relativeAge(_ iso: String) -> String {
        guard let date = PaseoDate.parse(iso) else { return "" }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 2 * 86_400 { return "1d" }
        if seconds < 7 * 86_400 { return "\(Int(seconds / 86_400))d" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private struct HistoryGroup: Identifiable {
        var id: String { label }
        var label: String
        var agents: [AgentSnapshot]
    }
}
#endif
