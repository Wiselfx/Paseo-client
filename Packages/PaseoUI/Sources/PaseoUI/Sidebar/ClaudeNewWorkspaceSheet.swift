#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The full new-workspace sheet in ClaudeUI's sheet chrome: pick a project (defaulting to the
/// selected workspace's project), an optional name, isolation (Local vs New worktree), the base
/// branch to fork from (free text, current branch prefilled — the store exposes branch
/// suggestions only per checkout, which this sheet does not have), and an optional first prompt,
/// which creates an agent in the new workspace right away with the catalogue's provider defaults.
struct ClaudeNewWorkspaceSheet: View {
    let session: HostSession
    let defaultProjectId: String?
    /// `agentId` when a first prompt produced an agent; `message` carries a toast line for
    /// partial failures (e.g. the workspace was created but the agent couldn't start).
    var onCreated: (String?, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var projectId: String?
    @State private var name = ""
    @State private var isolation: Isolation = .worktree
    @State private var baseBranchText = ""
    @State private var prompt = ""
    @State private var busyStep: BusyStep?
    private let typography = ClaudeTypography()

    enum Isolation: String, CaseIterable, Identifiable {
        case local
        case worktree

        var id: String { rawValue }

        var title: String {
            switch self {
            case .local: "Local"
            case .worktree: "New worktree"
            }
        }
    }

    enum BusyStep {
        case workspace
        case agent

        var label: String {
            switch self {
            case .workspace: "Creating workspace…"
            case .agent: "Creating agent…"
            }
        }
    }

    private var directory: WorkspaceDirectory { session.workspaceDirectory }
    private var catalog: AgentControlStore { session.agentControl }
    private var projects: [WorkspaceProjectDescriptor] { directory.projects }

    private var selectedProjectId: String {
        projectId ?? defaultProjectId ?? projects.first?.projectId ?? ""
    }

    private var selectedProject: WorkspaceProjectDescriptor? {
        projects.first { $0.projectId == selectedProjectId }
    }

    /// The branch a worktree forks from: the project's local (non-worktree) checkout branch,
    /// else any branch the directory carries, else "main". Used to prefill the base-branch field.
    private var currentBranch: String {
        let projectId = selectedProject?.projectId
        let workspaces = directory.workspaces.filter { $0.projectId == projectId }
        if let branch = workspaces.first(where: { $0.workspaceKind != .worktree && $0.branch != nil })?
            .branch
        {
            return branch
        }
        return workspaces.compactMap(\.branch).first ?? "main"
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        guard busyStep == nil, selectedProject != nil else { return false }
        if isolation == .worktree { return directory.supportsWorkspaceCreate }
        return true
    }

    var body: some View {
        VStack(spacing: 18) {
            SheetHeader(title: "New workspace", close: { dismiss() })
            ScrollView {
                VStack(spacing: 12) {
                    RowGroup {
                        HStack(spacing: 12) {
                            Text("Project")
                                .font(typography.sans(17))
                            Spacer(minLength: 8)
                            Picker(
                                "Project",
                                selection: Binding(
                                    get: { selectedProjectId },
                                    set: { projectId = $0 })
                            ) {
                                ForEach(projects) { project in
                                    Text(
                                        project.projectCustomName ?? project.projectDisplayName
                                    )
                                    .tag(project.projectId)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(typography.sans(16))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        RowDivider()
                        HStack(spacing: 12) {
                            Text("Name")
                                .font(typography.sans(17))
                            Spacer(minLength: 8)
                            TextField("Optional", text: $name)
                                .font(typography.sans(17))
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.words)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                    }
                    isolationSection
                    if isolation == .worktree {
                        baseBranchSection
                    }
                    promptSection
                    if let error = directory.actionError {
                        Text(error)
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    if let error = catalog.actionError {
                        Text(error)
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    createButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .onAppear {
            baseBranchText = currentBranch
            if !directory.supportsWorkspaceCreate { isolation = .local }
        }
        .onChange(of: selectedProjectId) { _, _ in
            baseBranchText = currentBranch
        }
    }

    private var isolationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Isolation")
                .font(typography.sans(13, weight: .medium))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .padding(.leading, 4)
            HStack(spacing: 2) {
                ForEach(Isolation.allCases) { option in
                    Button {
                        guard option == .local || directory.supportsWorkspaceCreate else { return }
                        Haptics.selection()
                        isolation = option
                    } label: {
                        Text(option.title)
                            .font(typography.sans(14, weight: isolation == option ? .medium : .regular))
                            .foregroundStyle(
                                isolation == option ? ClaudePalette.background : ClaudePalette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                isolation == option ? ClaudePalette.ink : Color.clear, in: .capsule)
                            .opacity(
                                option == .worktree && !directory.supportsWorkspaceCreate ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(option == .worktree && !directory.supportsWorkspaceCreate)
                    .accessibilityLabel(option.title)
                }
            }
            .padding(3)
            .background(ClaudePalette.chip, in: .capsule)
            if !directory.supportsWorkspaceCreate {
                Text("This daemon cannot create worktrees; new sessions open the project root.")
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.captionInk)
                    .padding(.leading, 4)
            }
        }
    }

    private var baseBranchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Branch off")
                .font(typography.sans(13, weight: .medium))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .padding(.leading, 4)
            RowGroup {
                HStack(spacing: 12) {
                    Text("Branch")
                        .font(typography.sans(17))
                    Spacer(minLength: 8)
                    TextField(
                        "", text: $baseBranchText,
                        prompt: Text("main").foregroundStyle(ClaudePalette.secondary)
                    )
                    .font(typography.mono(13))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
            }
            Text("The new worktree forks from this branch. The daemon reports no branch list here; type one.")
                .font(typography.sans(12))
                .foregroundStyle(ClaudePalette.captionInk)
                .padding(.horizontal, 4)
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("First prompt")
                .font(typography.sans(13, weight: .medium))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .padding(.leading, 4)
            RowGroup {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "", text: $prompt,
                        prompt: Text("What should the agent do?").foregroundStyle(ClaudePalette.secondary),
                        axis: .vertical
                    )
                    .font(typography.sans(16))
                    .lineLimit(1...4)
                    Text("Creates an agent right away with this host's default provider, model and mode.")
                        .font(typography.sans(11))
                        .foregroundStyle(ClaudePalette.captionInk)
                }
                .padding(12)
            }
        }
    }

    private var createButton: some View {
        Button {
            create()
        } label: {
            HStack(spacing: 8) {
                if busyStep != nil {
                    ProgressView().controlSize(.small).tint(ClaudePalette.background)
                }
                Text(busyStep?.label ?? "Create workspace")
                    .font(typography.sans(16, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(ClaudePalette.background)
            .background(ClaudePalette.ink, in: .capsule)
            .opacity(canCreate ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canCreate)
        .padding(.top, 4)
        .accessibilityIdentifier("newWorkspace.create")
    }

    private func create() {
        guard let project = selectedProject else { return }
        let title = trimmedName.isEmpty ? nil : trimmedName
        let prompt = trimmedPrompt
        let source: NewWorkspaceSource
        switch isolation {
        case .local:
            source = .local
        case .worktree:
            let typed = baseBranchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = typed.isEmpty ? currentBranch : typed
            let baseRef = base.hasPrefix("refs/") ? base : "refs/heads/\(base)"
            let branchName = branchSlug(trimmedName) ?? "workspace-\(Int(Date().timeIntervalSince1970))"
            source = .branchOff(baseRef: baseRef, branchName: branchName, worktreeSlug: branchName)
        }
        busyStep = .workspace
        Task {
            let created = await directory.createWorkspace(in: project, source: source, title: title)
            guard let workspace = created else {
                busyStep = nil
                return
            }
            var agentId: String?
            var message: String?
            if !prompt.isEmpty {
                busyStep = .agent
                agentId = await createAgent(in: workspace, prompt: prompt)
                if agentId == nil {
                    message = catalog.actionError ?? "Workspace created — but the agent couldn't start."
                }
            }
            await session.refreshAgents()
            onCreated(agentId, message)
            dismiss()
        }
    }

    /// Provider defaults as the new-agent sheet computes them: the first ready provider, its
    /// default model, thinking level and mode.
    private func createAgent(in workspace: WorkspaceDescriptor, prompt: String) async -> String? {
        let needsLoad: Bool
        switch catalog.phase {
        case .idle, .failed: needsLoad = true
        case .loading, .ready: needsLoad = catalog.providers.isEmpty
        }
        if needsLoad { await catalog.loadCatalog() }
        guard let providerId = catalog.readyProviders.first?.provider else {
            return nil
        }
        guard let model = catalog.defaultModel(forProvider: providerId) else {
            return nil
        }
        let thinking = model.defaultThinkingOptionId
        let mode =
            catalog.provider(providerId)?.defaultModeId
            ?? catalog.modes(forProvider: providerId).first?.id
        return await catalog.createAgent(
            cwd: workspace.cwd, workspaceId: workspace.id, provider: providerId, model: model.id,
            modeId: mode, thinkingOptionId: thinking, prompt: prompt)
    }

    /// Lowercase, non-alphanumerics collapsed to single dashes, trimmed; nil when nothing is left.
    private func branchSlug(_ raw: String) -> String? {
        let mapped = raw.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        var slug = String(mapped)
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        if slug.isEmpty { return nil }
        return String(slug.prefix(40))
    }
}
#endif
