#if canImport(UIKit)
import Foundation
import Observation
import PaseoStore
import SwiftUI
import UIKit

/// M9: the command center. A full-height search sheet over the sidebar: one field, grouped
/// results — Agents (live + archived), Workspaces, Projects, Files in the open workspace, and
/// Actions. Return opens the first/selected result; arrow keys on a hardware keyboard move the
/// highlight; an empty field shows recents. History, Schedules and Usage are always in Actions,
/// so hiding their sidebar rows never makes them unreachable (audit C #9).
struct CommandCenterSheet: View {
    let session: HostSession

    /// Opens the agent in the chat (the sidebar dismisses this sheet and selects it).
    let onOpenAgent: (String) -> Void
    /// Starts a session in the given workspace (the shell shows the new-session sheet).
    let onNewAgent: (WorkspaceDescriptor) -> Void
    /// Opens the New workspace sheet (replacing this sheet).
    let onNewWorkspace: () -> Void
    /// Opens Settings (replacing this sheet).
    let onOpenSettings: () -> Void
    /// Toggles the right-side workspace panel; nil hides the Toggle panel action.
    let onTogglePanel: (() -> Void)?
    /// Opens the Import session sheet; nil hides the action when the daemon lacks the feature.
    var onImportSession: (() -> Void)? = nil
    let onShowToast: (String) -> Void
    let onClose: () -> Void
    /// The agent open in the chat, if any; the Files group searches its workspace.
    let selectedAgentId: String?

    @Environment(\.hostSwitch) private var hostSwitch
    @Environment(\.toast) private var toast

    @State private var model = SearchModel()
    @State private var query = ""
    @FocusState private var fieldFocused: Bool
    @State private var selectedIndex = 0
    @State private var mentionIndex = MentionIndex()
    @State private var fileViewer: FileViewerTarget?
    /// A screen this sheet opened: History, Schedules and Usage are always reachable here.
    @State private var screen: Screen?
    @State private var hostExpanded = false

    enum Screen: String, Identifiable {
        case history
        case schedules
        case usage

        var id: String { rawValue }
    }

    var body: some View {
        SheetScaffold("Search", detents: .large, onClose: onClose) {
            VStack(spacing: 0) {
                searchField
                resultsList
            }
        }
        .sheet(item: $fileViewer) { target in
            WorkspaceFileViewer(
                checkout: target.checkout, relPath: target.relPath,
                onBack: { fileViewer = nil }, backLabel: "Search")
        }
        .sheet(item: $screen) { screen in
            switch screen {
            case .history:
                ClaudeHistoryView(
                    session: session,
                    onClose: { self.screen = nil },
                    onOpenAgent: { agentId in
                        self.screen = nil
                        onOpenAgent(agentId)
                    })
            case .schedules:
                ClaudeSchedulesView(session: session)
            case .usage:
                ClaudeUsageReportsSheet(session: session)
            }
        }
        .onAppear { refresh() }
        .task {
            fieldFocused = true
            if session.agentLifecycle.phase == .idle {
                await session.agentLifecycle.load()
            }
            if let workspace = openWorkspace {
                let checkout = session.checkout(for: workspace)
                await mentionIndex.build(using: checkout.files)
            }
            refresh()
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .task(id: query) {
            // 100 ms debounce: the sections are rebuilt once per settled query.
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            model.setQuery(query)
            selectedIndex = 0
        }
        // By value, not by count: the model caches titles, dots and recency, which a rename or a
        // status change alters without changing a count.
        .onChange(of: session.agents) { refresh() }
        .onChange(of: session.agentLifecycle.entries) { refresh() }
        .onChange(of: session.workspaceDirectory.workspaces) { refresh() }
        .onChange(of: session.workspaceDirectory.projects) { refresh() }
    }

    // MARK: Field

    private var searchField: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(.regular))
                .foregroundStyle(Palette.secondaryInk)
            TextField("Search agents, workspaces, files, actions…", text: $query)
                .focused($fieldFocused)
                .font(.paseo(.callout))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { activateSelection() }
                .onKeyPress(.downArrow) {
                    moveSelection(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(-1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
                .accessibilityLabel("Search")
                .accessibilityIdentifier("search.query")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.glyph(.regular))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Palette.chip, in: .capsule)
        .padding(.horizontal, Space.lg)
        .padding(.bottom, Space.sm)
        .accessibilityIdentifier("search.header")
    }

    // MARK: Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.flatRows.isEmpty {
                    EmptyState(
                        systemImage: "magnifyingglass",
                        title: model.noResultsText
                    )
                    .padding(.vertical, 36)
                    .accessibilityIdentifier("search.noResults")
                } else {
                    ForEach(model.sections) { section in
                        Section {
                            ForEach(section.rows) { row in
                                SearchResultRow(
                                    row: row, isSelected: row.id == selectedRowID,
                                    hostExpanded: hostExpanded
                                ) {
                                    activate(row)
                                }
                            }
                        } header: {
                            SearchSectionHeader(title: section.header)
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
    }

    /// The highlighted row's id, so a row compares one string instead of scanning the list.
    private var selectedRowID: String? {
        model.flatRows.indices.contains(selectedIndex)
            ? model.flatRows[selectedIndex].id : model.flatRows.first?.id
    }

    // MARK: Keyboard

    private func activateSelection() {
        guard !model.flatRows.isEmpty else { return }
        activate(model.flatRows[min(selectedIndex, model.flatRows.count - 1)])
    }

    private func moveSelection(_ delta: Int) {
        let count = model.flatRows.count
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }

    // MARK: Activation

    private func activate(_ row: SearchModel.Result) {
        selectedIndex = model.flatRows.firstIndex { $0.id == row.id } ?? selectedIndex
        switch row.kind {
        case .agent:
            guard let agent = row.agent else { return }
            openAgent(agent)
        case .workspace:
            guard let workspace = row.workspace else { return }
            openWorkspace(workspace)
        case .project:
            if let workspace = row.workspace {
                openWorkspace(workspace)
            } else {
                onNewWorkspace()
            }
        case .file:
            guard let mentionRow = row.fileRow, let workspace = openWorkspace else { return }
            fileViewer = FileViewerTarget(
                checkout: session.checkout(for: workspace), relPath: mentionRow.path)
        case .action:
            guard let action = row.action else { return }
            run(action)
        case .hostEntry:
            guard let entry = row.hostEntry, let hostSwitch else { return }
            onClose()
            hostSwitch.switchTo(entry.id)
        }
    }

    /// A live agent opens at once; an archived one unarchives first, and a failure is a toast.
    private func openAgent(_ agent: AgentSnapshot) {
        guard agent.archivedAt != nil else {
            onOpenAgent(agent.id)
            return
        }
        Task {
            if await session.agentLifecycle.unarchive(agentId: agent.id) {
                await session.refreshAgents()
                onOpenAgent(agent.id)
            } else {
                showToast(session.agentLifecycle.actionError ?? "Couldn't open the agent.")
            }
        }
    }

    /// The selected workspace's newest agent; an archived one unarchives first; none means a
    /// draft in that workspace (unchanged).
    private func openWorkspace(_ workspace: WorkspaceDescriptor) {
        let liveNewest = session.agents
            .filter { $0.workspaceId == workspace.id }
            .max { SearchModel.recency($0) < SearchModel.recency($1) }
        if let agent = liveNewest {
            onOpenAgent(agent.id)
            return
        }
        let archivedNewest = session.agentLifecycle.entries
            .filter { $0.workspaceId == workspace.id }
            .max { SearchModel.recency($0) < SearchModel.recency($1) }
        if let archived = archivedNewest {
            Task {
                if await session.agentLifecycle.unarchive(agentId: archived.id) {
                    await session.refreshAgents()
                    onOpenAgent(archived.id)
                } else {
                    showToast(session.agentLifecycle.actionError ?? "Couldn't open the agent.")
                }
            }
            return
        }
        onNewAgent(workspace)
    }

    private func run(_ action: SearchModel.CommandAction) {
        switch action {
        case .newSession:
            if let workspace = openWorkspace {
                onNewAgent(workspace)
            } else {
                showToast("Open a workspace to start an agent.")
            }
        case .newWorkspace:
            onNewWorkspace()
        case .importSession:
            onImportSession?()
        case .openHistory:
            screen = .history
        case .openSchedules:
            screen = .schedules
        case .openUsage:
            screen = .usage
        case .openSettings:
            onOpenSettings()
        case .togglePanel:
            onTogglePanel?()
            onClose()
        case .switchHost:
            hostExpanded.toggle()
            refresh()
        }
    }

    // MARK: Inputs

    private var openWorkspace: WorkspaceDescriptor? {
        guard
            let selected = selectedAgentId,
            let agent = session.agents.first(where: { $0.id == selected })
                ?? session.agentLifecycle.entries.first(where: { $0.id == selected }),
            let workspaceId = agent.workspaceId
        else { return nil }
        return session.workspaceDirectory.workspace(id: workspaceId)
    }

    private var actionList: [SearchModel.CommandAction] {
        SearchModel.CommandAction.allCases.filter { action in
            switch action {
            case .togglePanel: onTogglePanel != nil
            case .switchHost: hostSwitch != nil
            case .importSession: onImportSession != nil
            // History, Schedules and Usage are always here, whatever the sidebar shows.
            case .newSession, .newWorkspace, .openHistory, .openSchedules, .openUsage,
                .openSettings:
                true
            }
        }
    }

    /// `ToastCenter` draws above the sheet; the sidebar's toast is the fallback outside the shell.
    private func showToast(_ text: String) {
        if let toast {
            toast.show(text)
        } else {
            onShowToast(text)
        }
    }

    /// One pass over the session's data into the model: dates, activity and dots are precomputed.
    private func refresh() {
        var providerLabels: [String: String] = [:]
        for provider in session.agentControl.providers {
            providerLabels[provider.provider] = provider.label ?? provider.provider
        }
        model.update(
            agents: session.agents,
            workspaces: session.workspaceDirectory.workspaces,
            projects: session.workspaceDirectory.projects,
            files: mentionIndex,
            isLoadingFiles: mentionIndex.isBuilding,
            actions: actionList,
            hostEntries: hostSwitch?.hosts ?? [],
            hostExpanded: hostExpanded,
            providerLabels: providerLabels,
            fileWorkspaceID: openWorkspace?.id)
    }
}
#endif
