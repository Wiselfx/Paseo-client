#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI

/// Creates one agent inside the open workspace, with the provider/model/thinking/mode the host's
/// catalogue offers and the composer's text as the first prompt. Agents are not spread across new
/// workspaces: `workspaceId` and `cwd` come from the conversation you are in.
struct ClaudeNewAgentSheet: View {
    let session: HostSession
    let workspaceId: String?
    let cwd: String
    let initialPrompt: String
    var onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .root
    @State private var title = ""
    @State private var prompt: String
    @State private var form = ClaudeNewAgentForm()

    enum Page: Equatable { case root, providers, models, thinking, modes }

    init(
        session: HostSession, workspaceId: String?, cwd: String, initialPrompt: String,
        onCreated: @escaping (String) -> Void
    ) {
        self.session = session
        self.workspaceId = workspaceId
        self.cwd = cwd
        self.initialPrompt = initialPrompt
        self.onCreated = onCreated
        _prompt = State(initialValue: initialPrompt)
        ClaudeFontResources.register()
    }

    private var catalog: AgentControlStore { session.agentControl }

    private var models: [AgentModelDefinition] {
        guard let providerId = form.providerId else { return [] }
        return catalog.models(forProvider: providerId)
    }

    private var thinkingOptions: [ProviderThinkingOption] {
        guard let providerId = form.providerId, let modelId = form.modelId else { return [] }
        return catalog.thinkingOptions(forProvider: providerId, modelId: modelId)
    }

    private var modes: [AgentMode] {
        guard let providerId = form.providerId else { return [] }
        return catalog.modes(forProvider: providerId)
    }

    private var pageTitle: String {
        switch page {
        case .root: "New agent"
        case .providers: "Provider"
        case .models: "Model"
        case .thinking: "Thinking"
        case .modes: "Mode"
        }
    }

    private var canCreate: Bool {
        !form.creating && form.providerId != nil && form.modelId != nil
    }

    var body: some View {
        VStack(spacing: 16) {
            SheetHeader(
                title: pageTitle, back: page != .root,
                close: {
                    if page == .root {
                        dismiss()
                    } else {
                        page = .root
                    }
                })
            ScrollView {
                VStack(spacing: 12) {
                    switch page {
                    case .root: root
                    case .providers: providerPage
                    case .models: modelPage
                    case .thinking: thinkingPage
                    case .modes: modePage
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            if page == .root { createBar }
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .onAppear {
            Task { await form.load(session: session, cwd: cwd) }
        }
    }

    // MARK: Root

    private var root: some View {
        VStack(spacing: 12) {
            RowGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("First prompt")
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    TextField(
                        "", text: $prompt,
                        prompt: Text("What should the agent do?")
                            .foregroundStyle(ClaudePalette.secondary),
                        axis: .vertical
                    )
                    .font(.system(size: 17))
                    .lineLimit(2...8)
                }
                .padding(14)
                RowDivider()
                HStack(spacing: 12) {
                    Image(systemName: "textformat").font(.system(size: 18, weight: .light))
                        .foregroundStyle(ClaudePalette.secondary)
                        .frame(width: 23)
                    TextField("Title (optional)", text: $title)
                        .font(.system(size: 17))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
            }
            RowGroup {
                SheetRow(
                    title: "Provider", symbol: "server.rack", value: providerLabel, chevron: true
                ) { page = .providers }
                RowDivider()
                SheetRow(
                    title: "Model", symbol: "cpu", value: modelLabel, chevron: true
                ) { page = .models }
                RowDivider()
                SheetRow(
                    title: "Thinking", symbol: "brain", value: thinkingLabel, chevron: true
                ) { page = .thinking }
                RowDivider()
                SheetRow(
                    title: "Mode", symbol: "slider.horizontal.3", value: modeLabel, chevron: true
                ) { page = .modes }
            }
            if let error = form.error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("The agent starts in this workspace (\(cwd)).")
                .font(.system(size: 12))
                .foregroundStyle(ClaudePalette.captionInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
    }

    private var createBar: some View {
        Button {
            create()
        } label: {
            HStack(spacing: 8) {
                if form.creating {
                    ProgressView().controlSize(.small).tint(ClaudePalette.background)
                }
                Text(form.creating ? "Creating…" : "Create")
                    .font(.system(size: 16, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(ClaudePalette.background)
            .background(ClaudePalette.ink, in: .capsule)
            .opacity(canCreate ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canCreate)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .accessibilityIdentifier("newAgent.create")
    }

    // MARK: Pages

    private var providerPage: some View {
        RowGroup {
            let providers = catalog.readyProviders
            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                SheetRow(
                    title: provider.label ?? provider.provider,
                    symbol: "server.rack",
                    detail: provider.description,
                    checked: form.providerId == provider.provider
                ) {
                    Haptics.selection()
                    form.selectProvider(provider.provider, catalog: catalog)
                    page = .root
                }
                if index < providers.count - 1 { RowDivider() }
            }
        }
    }

    private var modelPage: some View {
        RowGroup {
            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                SheetRow(
                    title: model.label, detail: model.description,
                    checked: form.modelId == model.id,
                    badge: model.isDefault == true ? "Default" : nil
                ) {
                    Haptics.selection()
                    form.selectModel(model.id, catalog: catalog)
                    page = .root
                }
                if index < models.count - 1 { RowDivider() }
            }
        }
    }

    private var thinkingPage: some View {
        RowGroup {
            SheetRow(title: "Default", detail: "Use the provider's level for this model", checked: form.thinkingId == nil) {
                Haptics.selection()
                form.thinkingId = nil
                page = .root
            }
            ForEach(thinkingOptions) { option in
                RowDivider()
                SheetRow(
                    title: option.label, detail: option.description, checked: form.thinkingId == option.id
                ) {
                    Haptics.selection()
                    form.thinkingId = option.id
                    page = .root
                }
            }
        }
    }

    private var modePage: some View {
        RowGroup {
            ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                SheetRow(
                    title: mode.label, detail: mode.description, checked: form.modeId == mode.id
                ) {
                    Haptics.selection()
                    form.modeId = mode.id
                    page = .root
                }
                if index < modes.count - 1 { RowDivider() }
            }
        }
    }

    // MARK: Labels

    private var providerLabel: String {
        guard let providerId = form.providerId else { return "Select" }
        return catalog.provider(providerId)?.label ?? providerId
    }

    private var modelLabel: String {
        guard let modelId = form.modelId else { return "Select" }
        return models.first(where: { $0.id == modelId })?.label ?? modelId
    }

    private var thinkingLabel: String {
        guard let id = form.thinkingId else { return "Default" }
        return thinkingOptions.first(where: { $0.id == id })?.label ?? id
    }

    private var modeLabel: String {
        guard let id = form.modeId else { return "Default" }
        return modes.first(where: { $0.id == id })?.label ?? id
    }

    // MARK: Create

    private func create() {
        let title = title
        let prompt = prompt
        Task {
            guard
                let agentId = await form.create(
                    session: session, workspaceId: workspaceId, cwd: cwd, prompt: prompt, title: title)
            else { return }
            await session.refreshAgents()
            onCreated(agentId)
        }
    }
}

/// The new-agent form's choices. A small MainActor model so the async catalogue load can fill it
/// without the view's `@State` crossing actors.
@MainActor @Observable
final class ClaudeNewAgentForm {
    var providerId: String?
    var modelId: String?
    var thinkingId: String?
    var modeId: String?
    var creating = false
    var error: String?

    func load(session: HostSession, cwd: String) async {
        if session.agentControl.phase == .idle {
            await session.agentControl.loadCatalog(cwd: cwd)
        }
        if providerId == nil { providerId = session.agentControl.readyProviders.first?.provider }
        applyDefaults(session.agentControl)
    }

    func selectProvider(_ id: String, catalog: AgentControlStore) {
        providerId = id
        modelId = nil
        thinkingId = nil
        modeId = nil
        applyDefaults(catalog)
    }

    func selectModel(_ id: String, catalog: AgentControlStore) {
        modelId = id
        thinkingId = nil
        applyDefaults(catalog)
    }

    func applyDefaults(_ catalog: AgentControlStore) {
        guard let providerId else { return }
        if modelId == nil { modelId = catalog.defaultModel(forProvider: providerId)?.id }
        if thinkingId == nil, let modelId {
            thinkingId = catalog.models(forProvider: providerId)
                .first(where: { $0.id == modelId })?.defaultThinkingOptionId
        }
        if modeId == nil {
            modeId = catalog.provider(providerId)?.defaultModeId
                ?? catalog.modes(forProvider: providerId).first?.id
        }
    }

    func create(
        session: HostSession, workspaceId: String?, cwd: String, prompt: String, title: String
    ) async -> String? {
        guard let providerId else {
            error = "This host reports no available provider."
            return nil
        }
        guard let modelId else {
            error = "Pick a model for this provider."
            return nil
        }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        creating = true
        defer { creating = false }
        let agentId = await session.agentControl.createAgent(
            cwd: cwd,
            workspaceId: workspaceId,
            provider: providerId,
            model: modelId,
            modeId: modeId,
            thinkingOptionId: thinkingId,
            prompt: trimmedPrompt.isEmpty ? nil : trimmedPrompt,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle
        )
        error = agentId == nil ? (session.agentControl.actionError ?? "The daemon could not create the agent.") : nil
        return agentId
    }
}
#endif
