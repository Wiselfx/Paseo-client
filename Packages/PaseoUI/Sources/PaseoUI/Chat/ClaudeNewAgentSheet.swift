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

    enum Page: Equatable { case root, providers, models, thinking, modes, profiles }

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
        case .profiles: "Profile"
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
                    case .profiles: profilesPage
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
            if showsProfileRow {
                RowGroup {
                    SheetRow(
                        title: "Profile", symbol: "sparkles", value: profileLabel, chevron: true
                    ) { Haptics.selection(); page = .profiles }
                    .accessibilityIdentifier("newAgent.profile")
                }
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

    @ViewBuilder private var providerPage: some View {
        let providers = catalog.providers.filter(\.enabled)
        if providers.isEmpty {
            providerEmptyState
        } else {
            RowGroup {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    SheetRow(
                        title: provider.label ?? provider.provider,
                        symbol: "server.rack",
                        detail: providerDetail(provider),
                        checked: form.providerId == provider.provider,
                        badge: providerBadge(provider)
                    ) {
                        guard provider.isAvailable else { return }
                        Haptics.selection()
                        form.selectProvider(provider.provider, catalog: catalog)
                        page = .root
                    }
                    if index < providers.count - 1 { RowDivider() }
                }
            }
        }
    }

    /// Every provider the daemon reports is listed, in its order: one that is still probing says
    /// so and fills in through `providers_snapshot_update`. Only a ready one can be picked.
    @ViewBuilder private var providerEmptyState: some View {
        switch catalog.phase {
        case .loading, .idle:
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
        case .failed(let message):
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(ClaudePalette.failureInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        case .ready:
            Text("No enabled providers on this host.")
                .font(.system(size: 14))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private func providerDetail(_ provider: ProviderSnapshotEntry) -> String? {
        switch provider.status {
        case .ready: provider.description
        case .loading: "Loading models…"
        case .error: provider.error ?? "This provider could not start."
        case .unavailable: provider.error ?? "Not available on this host."
        case .unknown(let raw): raw.isEmpty ? nil : raw
        }
    }

    private func providerBadge(_ provider: ProviderSnapshotEntry) -> String? {
        switch provider.status {
        case .ready: nil
        case .loading: "Loading"
        case .error: "Error"
        case .unavailable: "Unavailable"
        case .unknown: nil
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
                form.profileId = nil
                page = .root
            }
            ForEach(thinkingOptions) { option in
                RowDivider()
                SheetRow(
                    title: option.label, detail: option.description, checked: form.thinkingId == option.id
                ) {
                    Haptics.selection()
                    form.thinkingId = option.id
                    form.profileId = nil
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
                    form.profileId = nil
                    page = .root
                }
                if index < modes.count - 1 { RowDivider() }
            }
        }
    }

    /// Named launch bundles from the host config: picking one prefills provider, model, mode,
    /// thinking and feature values once. "None" clears back to the defaults.
    private var profilesPage: some View {
        VStack(spacing: 12) {
            RowGroup {
                SheetRow(
                    title: "None",
                    detail: "Clear the profile and reset to the host's defaults",
                    checked: form.profileId == nil
                ) {
                    Haptics.selection()
                    form.clearProfile(catalog: catalog)
                    page = .root
                }
                .accessibilityIdentifier("newAgent.profile.none")
                ForEach(applicableProfiles) { profile in
                    RowDivider()
                    SheetRow(
                        title: profile.name,
                        detail: profileSummary(profile),
                        checked: form.profileId == profile.id
                    ) {
                        Haptics.selection()
                        form.applyProfile(profile, catalog: catalog)
                        page = .root
                    }
                    .accessibilityIdentifier("newAgent.profile.\(profile.id)")
                }
            }
            Text("Applies once at creation; you can change any field afterwards.")
                .font(.system(size: 12))
                .foregroundStyle(ClaudePalette.captionInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    /// "claude · Opus 5 · Plan · Think hard"-style line from the catalogue.
    private func profileSummary(_ profile: AgentProfile) -> String {
        var parts = [catalog.provider(profile.provider)?.label ?? profile.provider]
        if let model = profile.model, !model.isEmpty {
            let label = catalog.models(forProvider: profile.provider)
                .first(where: { $0.id == model })?.label ?? model
            parts.append(label)
        }
        if let modeId = profile.modeId, !modeId.isEmpty,
            let mode = catalog.modes(forProvider: profile.provider)
                .first(where: { $0.id == modeId }) {
            parts.append(mode.label)
        }
        if let thinkingId = profile.thinkingOptionId, !thinkingId.isEmpty,
            let modelId = profile.model ?? catalog.defaultModel(forProvider: profile.provider)?.id {
            let options = catalog.thinkingOptions(forProvider: profile.provider, modelId: modelId)
            parts.append(options.first(where: { $0.id == thinkingId })?.label ?? thinkingId)
        }
        if let notes = profile.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(notes)
        }
        return parts.joined(separator: " · ")
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

    private var profileLabel: String {
        guard let id = form.profileId else { return "None" }
        return session.hostSettings.profiles.first(where: { $0.id == id })?.name ?? "None"
    }

    /// Profiles exist only on daemons advertising `features.agentProfiles`, and only
    /// profiles whose provider this host offers are applicable (upstream hides the rest).
    /// Every listed profile applies once at creation; the user can change fields afterwards.
    private var applicableProfiles: [AgentProfile] {
        let all = session.hostSettings.profiles
        guard catalog.phase == .ready else { return all }
        return all.filter { catalog.provider($0.provider) != nil }
    }

    private var showsProfileRow: Bool {
        !session.hostSettings.profiles.isEmpty
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
    /// The profile last applied, if any. Any manual picker change clears it; "None" clears
    /// it too and restores the defaults.
    var profileId: String?
    /// Feature values carried by the applied profile. Captured here for the create RPC; this
    /// client's `AgentSessionConfig` cannot carry them yet (see the PARITY note for the gap).
    var featureValues: [String: JSONValue]?
    var creating = false
    var error: String?

    func load(session: HostSession, cwd: String) async {
        let catalog = session.agentControl
        // Retry after a failure or an empty catalogue (an old build advertised an app version the
        // daemon answered with only the legacy providers).
        let needsLoad: Bool
        switch catalog.phase {
        case .idle, .failed: needsLoad = true
        case .loading, .ready: needsLoad = catalog.providers.isEmpty
        }
        if needsLoad {
            await catalog.loadCatalog(cwd: cwd)
        }
        if providerId == nil { providerId = catalog.readyProviders.first?.provider }
        applyDefaults(catalog)
    }

    func selectProvider(_ id: String, catalog: AgentControlStore) {
        providerId = id
        modelId = nil
        thinkingId = nil
        modeId = nil
        profileId = nil
        applyDefaults(catalog)
    }

    func selectModel(_ id: String, catalog: AgentControlStore) {
        modelId = id
        thinkingId = nil
        profileId = nil
        applyDefaults(catalog)
    }

    /// Applies one profile, once, at creation: provider, model, mode, thinking and the
    /// profile's feature values. Each field is reconciled against the catalogue when it is
    /// loaded (upstream hides profiles the host cannot run); anything that does not resolve
    /// falls back to the catalogue default.
    func applyProfile(_ profile: AgentProfile, catalog: AgentControlStore) {
        profileId = profile.id
        featureValues = profile.featureValues
        providerId = profile.provider
        modelId = profile.model
        modeId = profile.modeId
        thinkingId = profile.thinkingOptionId

        if catalog.phase == .ready {
            let models = catalog.models(forProvider: profile.provider)
            if let modelId, !models.contains(where: { $0.id == modelId }) {
                self.modelId = nil
            }
            let modes = catalog.modes(forProvider: profile.provider)
            if let modeId, !modes.contains(where: { $0.id == modeId }) {
                self.modeId = nil
            }
        }
        applyDefaults(catalog)
        if let thinkingId, let providerId, let modelId {
            let options = catalog.thinkingOptions(forProvider: providerId, modelId: modelId)
            if options.isEmpty || !options.contains(where: { $0.id == thinkingId }) {
                self.thinkingId = nil
            }
        }
    }

    /// "None": drop the profile and any feature values it carried, back to a fresh default.
    func clearProfile(catalog: AgentControlStore) {
        profileId = nil
        featureValues = nil
        // Keep the current provider when the catalogue cannot name one (not loaded yet).
        providerId = catalog.readyProviders.first?.provider
            ?? catalog.providers.first { $0.enabled }?.provider
            ?? providerId
        modelId = nil
        thinkingId = nil
        modeId = nil
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
