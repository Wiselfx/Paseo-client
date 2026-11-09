#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The drawer: ClaudeUI's sidebar layout on `WorkspaceDirectory`'s project → workspace → agent
/// groups. Workspaces collapse, rows carry context menus, and the footer avatar opens Settings.
struct PaseoSidebar: View {
    let session: HostSession
    var selectedAgentId: String?
    var onSelectAgent: (String) -> Void
    var onNewAgent: (WorkspaceDescriptor) -> Void
    var onDisconnect: () -> Void

    @State private var sheet: PaseoSidebarSheet?
    @State private var renamingAgent: AgentSnapshot?
    @State private var renameText = ""
    @State private var toast: String?
    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    @AppStorage("paseo.sidebar.collapsedWorkspaces") private var collapsedWorkspaces = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let typography = ClaudeTypography()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Paseo")
                    .font(typography.serif(27))
                    .foregroundStyle(ClaudePalette.ink)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navigation
                    sectionHeader("Recents")
                    directory
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ClaudePalette.sidebarBackground)
        .foregroundStyle(ClaudePalette.ink)
        .sheet(item: $sheet) { selection in
            switch selection {
            case .settings:
                ClaudeSidebarSettingsSheet()
            case .comingSoon(let title):
                ClaudeSidebarComingSoonSheet(title: title)
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
                let target = renamingAgent
                let title = renameText
                renamingAgent = nil
                guard let target else { return }
                Task { await session.conversation(for: target.id).rename(to: title) }
            }
        } message: {
            Text("Choose a short name for this agent.")
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(typography.sans(13))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect()
                    .padding(.top, 58)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            guard !session.workspaceDirectory.hasLoaded, session.workspaceDirectory.error == nil else { return }
            Task { await session.workspaceDirectory.refresh() }
        }
    }

    // MARK: Navigation

    private var navigation: some View {
        VStack(spacing: 0) {
            navigationRow("Workspaces", symbol: "rectangle.stack") { sheet = .comingSoon("Workspaces") }
            navigationRow("Scheduled", symbol: "clock") { sheet = .comingSoon("Scheduled") }
            navigationRow("Settings", symbol: "gearshape") { sheet = .settings }
        }
        .padding(.top, 4)
    }

    private func navigationRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24)
                Text(title).font(typography.sans(18))
                Spacer(minLength: 0)
            }
            .frame(height: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Directory

    @ViewBuilder private var directory: some View {
        let groups = session.workspaceDirectory.groups
        if groups.isEmpty {
            if session.agents.isEmpty {
                Text(
                    session.workspaceDirectory.isLoading
                        ? "Loading workspaces…" : "No workspaces on this host yet."
                )
                .font(typography.sans(14))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .padding(.vertical, 24)
            } else {
                sectionHeader("Agents")
                ForEach(session.agents) { agent in agentRow(agent) }
            }
        } else {
            ForEach(groups) { group in
                sectionHeader(group.project.projectCustomName ?? group.project.projectDisplayName)
                ForEach(group.workspaces) { workspace in
                    workspaceRow(workspace)
                    SidebarAgentsRoll(expanded: isExpanded(workspace)) {
                        ForEach(agents(in: workspace)) { agent in agentRow(agent) }
                    }
                }
            }
        }
        if !unplacedAgents.isEmpty {
            sectionHeader("Other agents")
            ForEach(unplacedAgents) { agent in agentRow(agent) }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(typography.sans(15))
            .foregroundStyle(ClaudePalette.secondaryInk)
            .lineLimit(1)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    private func workspaceRow(_ workspace: WorkspaceDescriptor) -> some View {
        let expanded = isExpanded(workspace)
        return Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
                toggle(workspace)
            }
        } label: {
            HStack(spacing: 8) {
                PaseoStatusDot(kind: statusKind(workspace.status))
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(typography.sans(16, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                        Text(workspace.gitRuntime?.currentBranch ?? workspaceKindLabel(workspace))
                            .font(typography.sans(12))
                            .lineLimit(1)
                    }
                    .foregroundStyle(ClaudePalette.secondaryInk)
                }
                Spacer(minLength: 0)
                ClaudeChevron(expanded: expanded)
            }
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .contextMenu {
            Button("New agent here", systemImage: "plus") { onNewAgent(workspace) }
            Button("Copy path", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = workspace.cwd
                showToast("Path copied")
            }
            Button("Archive", systemImage: "archivebox", role: .destructive) {
                Task { await session.workspaceDirectory.archiveWorkspace(workspace.id) }
            }
        }
    }

    private func agents(in workspace: WorkspaceDescriptor) -> [AgentSnapshot] {
        session.agents.filter { $0.workspaceId == workspace.id }
    }

    private var unplacedAgents: [AgentSnapshot] {
        let known = Set(session.workspaceDirectory.workspaces.map(\.id))
        return session.agents.filter { agent in
            guard let workspaceId = agent.workspaceId else { return true }
            return !known.contains(workspaceId)
        }
    }

    // MARK: Collapse state

    private var collapsedSet: Set<String> {
        Set(collapsedWorkspaces.split(separator: ",").map(String.init))
    }

    private func isExpanded(_ workspace: WorkspaceDescriptor) -> Bool {
        !collapsedSet.contains(workspace.id)
    }

    private func toggle(_ workspace: WorkspaceDescriptor) {
        var collapsed = collapsedSet
        if collapsed.contains(workspace.id) {
            collapsed.remove(workspace.id)
        } else {
            collapsed.insert(workspace.id)
        }
        collapsedWorkspaces = collapsed.sorted().joined(separator: ",")
    }

    // MARK: Agents

    private func agentRow(_ agent: AgentSnapshot) -> some View {
        let selected = agent.id == selectedAgentId
        return Button {
            Haptics.selection()
            onSelectAgent(agent.id)
        } label: {
            HStack(spacing: 8) {
                PaseoStatusDot(kind: agentStatusKind(agent))
                Text(agent.title ?? "New agent")
                    .font(typography.sans(15, weight: selected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if agent.status == .running, agent.requiresAttention != true {
                    PaseoStatusDot(kind: .running)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 38)
            .foregroundStyle(ClaudePalette.ink)
            .contentShape(.rect)
            .background(selected ? ClaudePalette.chip : Color.clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(agent.title ?? "New agent")
        .accessibilityValue(agent.requiresAttention == true ? "Needs attention" : "")
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameText = agent.title ?? ""
                renamingAgent = agent
            }
            Button("Copy agent ID", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = agent.id
                showToast("Agent ID copied")
            }
            Button("Archive", systemImage: "archivebox", role: .destructive) {
                Task {
                    await session.conversation(for: agent.id).archive()
                    await session.refreshAgents()
                }
            }
        }
    }

    private func statusKind(_ status: WorkspaceStatusBucket) -> PaseoStatusDot.Kind {
        switch status {
        case .needsInput, .attention: .needsInput
        case .failed: .failed
        case .running: .running
        case .done: .done
        case .unknown: .idle
        }
    }

    private func agentStatusKind(_ agent: AgentSnapshot) -> PaseoStatusDot.Kind {
        switch agent.attention {
        case .permission: return .needsInput
        case .error: return .failed
        case .finished: return .unread
        case .unknown, nil: break
        }
        switch agent.status {
        case .running: return .running
        case .error: return .failed
        case .initializing, .idle, .closed, .unknown: return .idle
        }
    }

    private func workspaceKindLabel(_ workspace: WorkspaceDescriptor) -> String {
        switch workspace.workspaceKind {
        case .worktree: "Worktree"
        case .checkout, .localCheckout: "Checkout"
        case .directory: "Project root"
        case .unknown: "Workspace"
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                sheet = .settings
            } label: {
                ZStack {
                    Circle().fill(ClaudePalette.chip)
                    Text(initial)
                        .font(typography.serif(18, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            HStack(spacing: 6) {
                PaseoStatusDot(kind: connectionKind)
                Text(session.serverInfo?.hostname ?? "Paseo daemon")
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Disconnect", systemImage: "bolt.horizontal.circle", role: .destructive) { onDisconnect() }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Host options")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "P" }
        return String(first).uppercased()
    }

    private var connectionKind: PaseoStatusDot.Kind {
        switch session.connection {
        case .connected: .done
        case .reconnecting, .connecting: .running
        case .failed: .failed
        case .idle: .idle
        }
    }

    private func showToast(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = nil }
        }
    }
}

/// The DSH height roll for a workspace's agent rows: 200 ms, ease-out, measured naturally.
private struct SidebarAgentsRoll<Content: View>: View {
    let expanded: Bool
    @ViewBuilder var content: () -> Content

    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: SidebarAgentsHeightKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(SidebarAgentsHeightKey.self) { contentHeight = $0 }
            .frame(height: expanded ? contentHeight : 0, alignment: .top)
            .clipped()
            .opacity(expanded ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move), value: expanded)
    }
}

private struct SidebarAgentsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum PaseoSidebarSheet: Identifiable {
    case settings
    case comingSoon(String)

    var id: String {
        switch self {
        case .settings: "settings"
        case .comingSoon(let title): "coming.\(title)"
        }
    }
}

/// The screens that do not exist yet, in ClaudeUI's sheet chrome.
private struct ClaudeSidebarComingSoonSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    private let typography = ClaudeTypography()

    var body: some View {
        VStack(spacing: 18) {
            SheetHeader(title: title, close: { dismiss() })
            Spacer()
            Text("Coming soon")
                .font(typography.serif(24, relativeTo: .title2))
                .foregroundStyle(ClaudePalette.ink)
            Text("This screen isn't built yet.")
                .font(typography.sans(14))
                .foregroundStyle(ClaudePalette.secondaryInk)
            Spacer()
        }
        .background(ClaudePalette.background)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
    }
}

/// Appearance and the optional name the home greeting uses. The rest of Settings is still to come.
private struct ClaudeSidebarSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PaseoSettingsKeys.appearance) private var appearance = ClaudeAppearance.system.rawValue
    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    private let typography = ClaudeTypography()

    var body: some View {
        VStack(spacing: 18) {
            SheetHeader(title: "Settings", close: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Appearance")
                    RowGroup {
                        HStack {
                            Text("Theme")
                                .font(typography.sans(17))
                            Spacer(minLength: 8)
                            Picker("Theme", selection: $appearance) {
                                ForEach(ClaudeAppearance.allCases, id: \.self) { choice in
                                    Text(choice.rawValue).tag(choice.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(typography.sans(16))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                    }
                    sectionTitle("Your name")
                    RowGroup {
                        HStack {
                            Text("Name")
                                .font(typography.sans(17))
                            Spacer(minLength: 8)
                            TextField("Your name", text: $name)
                                .font(typography.sans(17))
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.words)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                    }
                    Text("Used in the greeting on the home screen.")
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.captionInk)
                    Text("Scheduled and Workspaces settings are coming soon.")
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(typography.sans(13, weight: .medium))
            .foregroundStyle(ClaudePalette.secondaryInk)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }
}

/// 6 pt dot: breathing while running, yellow for input, blue for unread, hollow for idle.
struct PaseoStatusDot: View {
    enum Kind: Equatable { case running, needsInput, failed, done, unread, idle }

    let kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Group {
            switch kind {
            case .running:
                Circle().fill(ClaudePalette.secondaryInk).frame(width: 6, height: 6)
                    .opacity(breathing ? 1 : 0.3)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: breathing)
                    .onAppear { breathing = true }
            case .needsInput: Circle().fill(ClaudePalette.warning).frame(width: 6, height: 6)
            case .failed: Circle().fill(ClaudePalette.failureInk).frame(width: 6, height: 6)
            case .done: Circle().fill(ClaudePalette.successInk).frame(width: 6, height: 6)
            case .unread: Circle().fill(ClaudePalette.unread).frame(width: 6, height: 6)
            case .idle: Circle().strokeBorder(ClaudePalette.captionInk, lineWidth: 1).frame(width: 6, height: 6)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}
#endif
