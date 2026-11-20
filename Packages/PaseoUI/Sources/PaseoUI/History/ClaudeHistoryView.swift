#if canImport(UIKit)
import Foundation
import Observation
import PaseoStore
import SwiftUI

/// The History screen: every agent on this host — live and archived — grouped by day, with a
/// debounced title filter. Row verbs follow PLAN §RH: Open, Rename…, Copy agent id, then the
/// destructive verb.
struct ClaudeHistoryView: View {
    let session: HostSession
    let onClose: () -> Void
    /// Tap row → the sidebar dismisses this sheet and selects the agent.
    let onOpenAgent: (String) -> Void

    @Environment(\.toast) private var toast

    @State private var model = HistoryModel()
    @State private var searchText = ""
    @State private var renamingAgent: AgentSnapshot?
    @State private var renameText = ""
    @State private var agentPendingArchive: AgentSnapshot?
    @State private var agentPendingDelete: AgentSnapshot?
    @State private var unarchivingAgentID: String?

    private var lifecycle: AgentLifecycleStore { session.agentLifecycle }

    var body: some View {
        SheetScaffold("History", detents: .large, onClose: onClose) {
            VStack(spacing: 0) {
                searchField
                content
            }
        }
        .task {
            rebuild()
            if lifecycle.phase == .idle {
                await lifecycle.load()
                rebuild()
            }
        }
        .onChange(of: lifecycle.entries.count) { _, _ in rebuild() }
        .onChange(of: lifecycle.entries.last?.id) { _, _ in rebuild() }
        .task(id: searchText) {
            // 120 ms debounce: the filter runs on the precomputed keys only.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            model.applyFilter(searchText)
        }
        .alert(
            "Rename agent",
            item: $renamingAgent
        ) { _ in
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingAgent = nil }
            Button("Rename") {
                guard let agent = renamingAgent else { return }
                let next = renameText
                renamingAgent = nil
                Task { await lifecycle.rename(agentId: agent.id, to: next) }
            }
        } message: { _ in
            Text("Choose a short name for this agent.")
        }
        .confirmationDialog(
            "Archive agent?",
            item: $agentPendingArchive,
            titleVisibility: .visible
        ) { _ in
            Button("Archive", role: .destructive) {
                guard let agent = agentPendingArchive else { return }
                agentPendingArchive = nil
                Task { await archive(agent) }
            }
            Button("Cancel", role: .cancel) { agentPendingArchive = nil }
        } message: { _ in
            Text("This agent is still running. Archiving it will stop the agent.")
        }
        .confirmationDialog(
            "Delete agent?",
            item: $agentPendingDelete,
            titleVisibility: .visible
        ) { _ in
            Button("Delete permanently", role: .destructive) {
                guard let agent = agentPendingDelete else { return }
                agentPendingDelete = nil
                Task { await delete(agent) }
            }
            Button("Cancel", role: .cancel) { agentPendingDelete = nil }
        } message: { _ in
            Text("This removes its history for good.")
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(.small))
                .foregroundStyle(Palette.secondaryInk)
            TextField("Search history", text: $searchText)
                .font(.paseo(.callout))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("history.search")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.glyph(.small))
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.md)
        .frame(height: 44)
        .background(Palette.chip, in: .rect(cornerRadius: Radius.sm))
        .padding(.horizontal, Space.lg)
        .padding(.bottom, Space.sm)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch lifecycle.phase {
        case .idle, .loading:
            LoadingState("Loading history…")
        case .failed(let message):
            EmptyState(
                systemImage: "exclamationmark.circle",
                title: "Couldn't load agent history",
                message: message,
                action: (title: "Try again", run: { Task { await lifecycle.load(); rebuild() } })
            )
        case .ready:
            if model.isEmpty {
                emptyState
            } else if model.groups.isEmpty {
                EmptyState(
                    systemImage: "clock.arrow.2.circlepath",
                    title: "No sessions match",
                    message: "Try a different title."
                )
            } else {
                list
            }
        }
    }

    private var emptyState: some View {
        EmptyState(
            systemImage: "clock.arrow.2.circlepath",
            title: "No sessions yet",
            message: "Start one from the sidebar."
        )
    }

    private var list: some View {
        PageList {
            ForEach(model.groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        rowView(row)
                    }
                } header: {
                    Text(group.label)
                }
            }
            if lifecycle.hasMore {
                Button {
                    Task {
                        await lifecycle.loadMore()
                        rebuild()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if lifecycle.isLoadingMore {
                            InlineProgress()
                        } else {
                            Text("Load more")
                                .font(.paseo(.callout, weight: .medium))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        Spacer()
                    }
                    .frame(minHeight: 44)
                }
                .panelRow(Palette.background)
                .accessibilityLabel("Load more")
            }
        }
        .refreshable {
            await lifecycle.load()
            rebuild()
        }
    }

    // MARK: Rows

    private func rowView(_ row: HistoryModel.Row) -> some View {
        HStack(spacing: 0) {
            ListRow(title: row.title, subtitle: row.subtitle, action: { requestOpen(row) })
            trailing(row)
        }
        .panelRow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.archived ? "Archived agent" : "Open agent") \(row.title)")
        .contextMenu { rowMenu(row) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if row.archived {
                Button(role: .destructive) {
                    agentPendingDelete = row.agent
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    requestArchive(row.agent)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }
        }
    }

    @ViewBuilder private func trailing(_ row: HistoryModel.Row) -> some View {
        if unarchivingAgentID == row.id {
            InlineProgress()
                .padding(.trailing, Space.lg)
        } else {
            VStack(alignment: .trailing, spacing: Space.xs) {
                if row.archived {
                    Text("Archived")
                        .font(.paseo(.caption2, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 2)
                        .background(Palette.chip, in: .capsule)
                }
                Text(row.date.map(relativeAge) ?? "")
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.captionInk)
            }
            .padding(.trailing, Space.lg)
        }
    }

    @ViewBuilder private func rowMenu(_ row: HistoryModel.Row) -> some View {
        Button {
            requestOpen(row)
        } label: {
            Label("Open", systemImage: "arrow.up.forward.app")
        }
        Button {
            beginRename(row.agent)
        } label: {
            Label("Rename…", systemImage: "pencil")
        }
        Button {
            Clipboard.copy(row.agent.id)
            toast?.show("Agent ID copied")
        } label: {
            Label("Copy agent ID", systemImage: "doc.on.doc")
        }
        Divider()
        if row.archived {
            Button(role: .destructive) {
                agentPendingDelete = row.agent
            } label: {
                Label("Delete permanently", systemImage: "trash")
            }
        } else {
            Button(role: .destructive) {
                requestArchive(row.agent)
            } label: {
                Label("Archive agent", systemImage: "archivebox")
            }
        }
    }

    // MARK: Actions

    /// A live row opens at once; an archived one shows the row's progress while it unarchives.
    private func requestOpen(_ row: HistoryModel.Row) {
        guard row.archived else {
            onOpenAgent(row.id)
            return
        }
        unarchivingAgentID = row.id
        Task {
            if await lifecycle.unarchive(agentId: row.id) {
                await session.refreshAgents()
                unarchivingAgentID = nil
                onOpenAgent(row.id)
            } else {
                unarchivingAgentID = nil
                toast?.show(lifecycle.actionError ?? "Couldn't open the agent.")
            }
        }
    }

    /// R6: confirm only while running; otherwise archive at once and offer Undo.
    private func requestArchive(_ agent: AgentSnapshot) {
        if agent.status == .running {
            agentPendingArchive = agent
            return
        }
        Task { await archive(agent) }
    }

    private func archive(_ agent: AgentSnapshot) async {
        guard await lifecycle.archive(agentId: agent.id) else {
            toast?.show(lifecycle.actionError ?? "Couldn't archive the agent.")
            return
        }
        await session.refreshAgents()
        Haptics.light()
        toast?.show("Archived \(HistoryModel.title(for: agent))", undo: {
            Task {
                if await lifecycle.unarchive(agentId: agent.id) {
                    await session.refreshAgents()
                }
            }
        })
    }

    private func delete(_ agent: AgentSnapshot) async {
        guard await lifecycle.delete(agentId: agent.id) else {
            toast?.show(lifecycle.actionError ?? "Couldn't delete the agent.")
            return
        }
        await session.refreshAgents()
    }

    private func beginRename(_ agent: AgentSnapshot) {
        renameText = HistoryModel.title(for: agent)
        renamingAgent = agent
    }

    /// `2m ago`, `yesterday`: `PaseoFormat` owns the wording (UX-SPEC §0.2).
    private func relativeAge(_ date: Date) -> String {
        PaseoFormat.relative(date)
    }

    // MARK: Rebuild

    /// Feeds the model the values it needs; it does the parsing and grouping once.
    private func rebuild() {
        var workspaceTitles: [String: String] = [:]
        for workspace in session.workspaceDirectory.workspaces {
            let title = workspace.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            workspaceTitles[workspace.id] = (title?.isEmpty == false ? title : nil)
                ?? workspace.name
        }
        var providerLabels: [String: String] = [:]
        for provider in session.agentControl.providers {
            providerLabels[provider.provider] = provider.label ?? provider.provider
        }
        let catalog = session.agentControl
        model.rebuild(
            entries: lifecycle.entries,
            workspaceTitles: workspaceTitles,
            providerLabels: providerLabels,
            modelLabel: { provider, model in
                catalog.models(forProvider: provider).first(where: { $0.id == model })?.label
                    ?? model
            })
    }
}
#endif
