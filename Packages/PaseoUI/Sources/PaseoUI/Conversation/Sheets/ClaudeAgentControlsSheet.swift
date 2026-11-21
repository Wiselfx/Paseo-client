#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// ClaudeUI's picker chrome fed by the daemon's provider catalogue: model (with provider default),
/// thinking level, and the agent's mode. Every pick goes through `ConversationStore`.
struct ClaudeAgentControlsSheet: View {
    let session: HostSession
    let store: ConversationStore

    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .root
    /// Bumped by every pick, so the selection haptic is a sensory feedback of this view. The
    /// increment is synchronous, so it plays before the pick's `dismiss()`.
    @State private var pickPulse = 0

    enum Page: Equatable { case root, models, thinking, modes, features, feature(String) }

    private var providerId: String? {
        if let id = store.agent?.provider, !id.isEmpty { return id }
        return session.agentControl.readyProviders.first?.provider
    }

    private var models: [AgentModelDefinition] {
        guard let providerId else { return [] }
        return session.agentControl.models(forProvider: providerId)
    }

    /// The provider entry the daemon reported for this agent's provider, if the catalogue holds it.
    private var providerEntry: ProviderSnapshotEntry? {
        guard let providerId else { return nil }
        return session.agentControl.provider(providerId)
    }

    private var providerIsLoading: Bool { providerEntry?.status == .loading }

    private var thinkingOptions: [ProviderThinkingOption] {
        guard let providerId, let modelId = store.agent?.model else { return [] }
        return session.agentControl.thinkingOptions(forProvider: providerId, modelId: modelId)
    }

    private var modes: [AgentMode] {
        if let modes = store.agent?.availableModes, !modes.isEmpty { return modes }
        guard let providerId else { return [] }
        return session.agentControl.modes(forProvider: providerId)
    }

    private var title: String {
        switch page {
        case .root: "Agent"
        case .models: "Model"
        case .thinking: "Thinking"
        case .modes: "Mode"
        case .features: "Features"
        case .feature: selectFeature?.label ?? "Feature"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            SheetHeader(
                title: title, back: page != .root,
                close: {
                    switch page {
                    case .root:
                        dismiss()
                    case .feature:
                        page = .features
                    default:
                        page = .root
                    }
                })
            content
            Spacer(minLength: 0)
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .paseoFeedback(.selection, trigger: pickPulse)
        // The root page scrolls, and `.large` is there for accessibility text sizes and short
        // windows where 430 pt cannot hold its rows.
        .presentationDetents([.height(430), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            let catalog = session.agentControl
            let providerMissing = store.agent.map { catalog.provider($0.provider) == nil } ?? true
            switch catalog.phase {
            case .idle, .failed:
                let cwd = store.agent?.cwd
                Task { await catalog.loadCatalog(cwd: cwd) }
            case .loading, .ready:
                // Another screen may have loaded a catalogue for a different workspace.
                if providerMissing {
                    let cwd = store.agent?.cwd
                    Task { await catalog.loadCatalog(cwd: cwd) }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch session.agentControl.phase {
        case .loading where session.agentControl.providers.isEmpty:
            ProgressView().frame(maxWidth: .infinity).padding(.top, Space.xxl)
        case .failed(let message) where session.agentControl.providers.isEmpty:
            Text(message)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.failureInk)
                .padding(.horizontal, Space.lg)
        default:
            switch page {
            case .root:
                ScrollView {
                    AgentControlsRootPage(
                        providerDetail: providerDetail,
                        modelValue: modelLabel(store.agent?.model),
                        thinkingValue: thinkingLabel,
                        modeValue: modeLabel,
                        featuresSummary: hasFeatures ? featuresSummary : nil,
                        onSelect: { page = $0 })
                }
            case .models:
                AgentModelPage(
                    models: models, currentModelId: store.agent?.model,
                    isProviderLoading: providerIsLoading, onPick: { pickModel($0) })
            case .thinking:
                AgentThinkingPage(
                    options: thinkingOptions, effectiveId: effectiveThinkingId,
                    isProviderLoading: providerIsLoading, onChoose: { chooseThinking($0) })
            case .modes:
                AgentModePage(
                    modes: modes, currentModeId: store.agent?.currentModeId, onPick: { pickMode($0) })
            case .features:
                AgentFeaturesPage(
                    toggles: toggleableFeatures, selects: selectableFeatures,
                    onToggle: { setFeatureToggle($0, $1) },
                    onOpenSelect: { page = .feature($0) })
            case .feature:
                AgentFeatureSelectPage(select: selectFeature, onPick: { pickFeatureSelection($0, $1) })
            }
        }
    }

    private var agentFeatures: [AgentFeature] {
        store.agent?.features ?? []
    }

    /// The feature behind the current `.feature` page, or nil.
    private var selectFeature: AgentFeature.Select? {
        guard case .feature(let id) = page else { return nil }
        for feature in agentFeatures {
            if case .select(let select) = feature, select.id == id { return select }
        }
        return nil
    }

    private var toggleableFeatures: [AgentFeature.Toggle] {
        agentFeatures.compactMap { if case .toggle(let toggle) = $0 { return toggle } else { return nil } }
    }

    private var selectableFeatures: [AgentFeature.Select] {
        agentFeatures.compactMap { if case .select(let select) = $0 { return select } else { return nil } }
    }

    private var hasFeatures: Bool {
        !toggleableFeatures.isEmpty || !selectableFeatures.isEmpty
    }

    private var featuresSummary: String {
        let on = toggleableFeatures.count(where: \.value)
        return "\(on) on"
    }

    private var providerDetail: String? {
        guard let providerId else { return nil }
        let label = session.agentControl.provider(providerId)?.label ?? providerId
        return "Provider · \(label)"
    }

    private var effectiveThinkingId: String? {
        guard let agent = store.agent else { return nil }
        return agent.effectiveThinkingOptionId ?? agent.thinkingOptionId
    }

    private var thinkingLabel: String {
        guard let id = effectiveThinkingId else { return "Default" }
        return thinkingOptions.first(where: { $0.id == id })?.label ?? id
    }

    private var modeLabel: String {
        guard let id = store.agent?.currentModeId else { return "Default" }
        return modes.first(where: { $0.id == id })?.label ?? id
    }

    private func modelLabel(_ id: String?) -> String {
        guard let providerId else { return id ?? "Default" }
        if let id, let match = models.first(where: { $0.id == id }) { return match.label }
        return session.agentControl.defaultModel(forProvider: providerId)?.label ?? id ?? "Default"
    }

    private func pickModel(_ id: String) {
        pickPulse += 1
        Task {
            await store.setModel(id)
            dismiss()
        }
    }

    private func chooseThinking(_ id: String?) {
        pickPulse += 1
        Task {
            await store.setThinking(id)
            dismiss()
        }
    }

    private func pickMode(_ id: String) {
        pickPulse += 1
        Task {
            await store.setMode(id)
            dismiss()
        }
    }

    private func setFeatureToggle(_ featureId: String, _ value: Bool) {
        pickPulse += 1
        Task { await store.setFeatureToggle(featureId: featureId, value: value) }
    }

    private func pickFeatureSelection(_ featureId: String, _ value: String?) {
        pickPulse += 1
        page = .features
        Task { await store.setFeatureSelection(featureId: featureId, value: value) }
    }
}
#endif
