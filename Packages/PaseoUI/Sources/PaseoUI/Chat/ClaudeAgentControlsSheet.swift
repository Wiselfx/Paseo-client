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
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
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
            ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
        case .failed(let message) where session.agentControl.providers.isEmpty:
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(ClaudePalette.failureInk)
                .padding(.horizontal, 16)
        default:
            switch page {
            case .root: root
            case .models: modelPage
            case .thinking: thinkingPage
            case .modes: modePage
            case .features: featuresPage
            case .feature: featureSelectPage
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

    private var root: some View {
        VStack(spacing: 12) {
            RowGroup {
                SheetRow(
                    title: "Model", detail: providerDetail,
                    value: modelLabel(store.agent?.model), chevron: true
                ) { page = .models }
                RowDivider()
                SheetRow(
                    title: "Thinking", value: thinkingLabel, chevron: true
                ) { page = .thinking }
                RowDivider()
                SheetRow(
                    title: "Mode", value: modeLabel, chevron: true
                ) { page = .modes }
                if !toggleableFeatures.isEmpty || !selectableFeatures.isEmpty {
                    RowDivider()
                    SheetRow(
                        title: "Features", value: featuresSummary, chevron: true
                    ) { page = .features }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var toggleableFeatures: [AgentFeature.Toggle] {
        agentFeatures.compactMap { if case .toggle(let toggle) = $0 { return toggle } else { return nil } }
    }

    private var selectableFeatures: [AgentFeature.Select] {
        agentFeatures.compactMap { if case .select(let select) = $0 { return select } else { return nil } }
    }

    private var featuresSummary: String {
        let on = toggleableFeatures.filter(\.value).count
        return "\(on) on"
    }

    private var providerDetail: String? {
        guard let providerId else { return nil }
        let label = session.agentControl.provider(providerId)?.label ?? providerId
        return "Provider · \(label)"
    }

    private var modelPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                if models.isEmpty {
                    VStack(spacing: 8) {
                        if providerIsLoading { ProgressView().controlSize(.small) }
                        Text(
                            providerIsLoading
                                ? "Loading models from this provider…"
                                : "No models reported by this provider"
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    }
                    .padding(.top, 24)
                } else {
                    RowGroup {
                        ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                            SheetRow(
                                title: model.label,
                                detail: model.description,
                                checked: store.agent?.model == model.id,
                                badge: model.isDefault == true ? "Default" : nil
                            ) {
                                Haptics.selection()
                                Task {
                                    await store.setModel(model.id)
                                    dismiss()
                                }
                            }
                            if index < models.count - 1 { RowDivider() }
                        }
                    }
                    .padding(.horizontal, 16)
                    Text("Model ids are provider-defined; the list comes from the host's catalogue.")
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private var thinkingPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let ranked = EffortLadder.ranked(thinkingOptions) {
                    // Compact Faster ↔ Smarter ladder (effort). The list remains for unranked providers.
                    EffortLadder(
                        options: ranked,
                        selectedId: effectiveThinkingId
                    ) { chooseThinking($0) }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                } else {
                    plainThinkingList
                }
            }
        }
    }

    /// The original list of options — used when the provider's levels aren't ranked.
    private var plainThinkingList: some View {
        VStack(spacing: 12) {
                RowGroup {
                    SheetRow(
                        title: "Default", detail: "Use the provider's level for this model",
                        checked: effectiveThinkingId == nil
                    ) {
                        chooseThinking(nil)
                    }
                    ForEach(thinkingOptions) { option in
                        RowDivider()
                        SheetRow(
                            title: option.label, detail: option.description,
                            checked: effectiveThinkingId == option.id,
                            badge: option.isDefault == true ? "Default" : nil
                        ) {
                            chooseThinking(option.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                if thinkingOptions.isEmpty {
                    Text(
                        providerIsLoading
                            ? "Waiting for this provider's model list…"
                            : "This model reports no thinking levels."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.horizontal, 16)
                }
        }
    }

    // MARK: Features

    /// Feature switches from the snapshot: toggle rows with a switch, select rows as menus of
    /// options. Unknown feature kinds are not shown.
    private var featuresPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                if toggleableFeatures.isEmpty, selectableFeatures.isEmpty {
                    Text("This agent doesn't offer any features.")
                        .font(.system(size: 14))
                        .foregroundStyle(ClaudePalette.secondary)
                        .padding(.top, 24)
                } else {
                    RowGroup {
                        ForEach(Array(toggleableFeatures.enumerated()), id: \.element.id) { index, toggle in
                            featureToggleRow(toggle)
                            if index < toggleableFeatures.count - 1 || !selectableFeatures.isEmpty { RowDivider() }
                        }
                        ForEach(Array(selectableFeatures.enumerated()), id: \.element.id) { index, select in
                            SheetRow(
                                title: select.label, detail: select.description,
                                value: selectValueLabel(select), chevron: true
                            ) { page = .feature(select.id) }
                            if index < selectableFeatures.count - 1 { RowDivider() }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func featureToggleRow(_ toggle: AgentFeature.Toggle) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(toggle.label)
                    .font(.system(size: 17))
                if let detail = toggle.description {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let tooltip = toggle.tooltip {
                    Text(tooltip)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Toggle(
                "",
                isOn: Binding(
                    get: { toggle.value },
                    set: { newValue in
                        Haptics.selection()
                        Task { await store.setFeatureToggle(featureId: toggle.id, value: newValue) }
                    })
            )
            .labelsHidden()
            .tint(.blue)
            .accessibilityLabel(toggle.label)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var featureSelectPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let select = selectFeature {
                    RowGroup {
                        if select.value != nil {
                            SheetRow(title: "None") {
                                Haptics.selection()
                                page = .features
                                Task { await store.setFeatureSelection(featureId: select.id, value: nil) }
                            }
                            RowDivider()
                        }
                        ForEach(Array(select.options.enumerated()), id: \.element.id) { index, option in
                            SheetRow(
                                title: option.label, detail: option.description,
                                checked: select.value == option.id,
                                badge: option.isDefault == true ? "Default" : nil
                            ) {
                                Haptics.selection()
                                page = .features
                                Task {
                                    await store.setFeatureSelection(
                                        featureId: select.id, value: option.id)
                                }
                            }
                            if index < select.options.count - 1 { RowDivider() }
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    Text("This feature is gone — the agent changed its feature set.")
                        .font(.system(size: 14))
                        .foregroundStyle(ClaudePalette.secondary)
                        .padding(.top, 24)
                }
            }
        }
    }

    private func selectValueLabel(_ select: AgentFeature.Select) -> String {
        guard let value = select.value else { return "None" }
        return select.options.first(where: { $0.id == value })?.label ?? value
    }

    private var modePage: some View {
        ScrollView {
            VStack(spacing: 12) {
                RowGroup {
                    ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                        SheetRow(
                            title: mode.label, detail: mode.description,
                            checked: store.agent?.currentModeId == mode.id
                        ) {
                            Haptics.selection()
                            Task {
                                await store.setMode(mode.id)
                                dismiss()
                            }
                        }
                        if index < modes.count - 1 { RowDivider() }
                    }
                }
                .padding(.horizontal, 16)
                if modes.isEmpty {
                    Text("This agent reports no modes.")
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
                        .padding(.horizontal, 16)
                }
            }
        }
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

    private func chooseThinking(_ id: String?) {
        Haptics.selection()
        Task {
            await store.setThinking(id)
            dismiss()
        }
    }
}
#endif
