#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The draft's agent settings (UX-SPEC §3.1): provider, model, thinking and mode. The provider is
/// offered **only** before creation; once the session is bound to its harness the live agent's
/// sheet (`ClaudeAgentControlsSheet`) shows the model only, as upstream does.
///
/// Thinking is the same one-row-per-level list the live sheet uses (§4.2), never a slider.
struct DraftControlsSheet: View {
    let session: HostSession
    @Bindable var draft: DraftSession

    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .root

    enum Page: Equatable { case root, providers, models, thinking, modes }

    private var catalog: AgentControlStore { session.agentControl }

    private var providers: [ProviderSnapshotEntry] {
        catalog.providers.filter(\.enabled)
    }

    private var models: [AgentModelDefinition] {
        guard let providerId = draft.providerId else { return [] }
        return catalog.models(forProvider: providerId)
    }

    private var thinkingOptions: [ProviderThinkingOption] {
        guard let providerId = draft.providerId, let modelId = draft.modelId else { return [] }
        return catalog.thinkingOptions(forProvider: providerId, modelId: modelId)
    }

    private var modes: [AgentMode] {
        guard let providerId = draft.providerId else { return [] }
        return catalog.modes(forProvider: providerId)
    }

    private var title: String {
        switch page {
        case .root: "Agent"
        case .providers: "Provider"
        case .models: "Model"
        case .thinking: "Thinking"
        case .modes: "Mode"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            SheetHeader(
                title: title, back: page != .root,
                close: {
                    if page == .root {
                        dismiss()
                    } else {
                        page = .root
                    }
                })
            content
            Spacer(minLength: 0)
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.visible)
        .onAppear {
            // The draft's sheet can open before the conversation ever asked for a catalogue.
            if catalog.providers.isEmpty {
                let cwd = draft.cwd
                Task { await catalog.loadCatalog(cwd: cwd.isEmpty ? nil : cwd) }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .root: root
        case .providers: providerPage
        case .models: modelPage
        case .thinking: thinkingPage
        case .modes: modePage
        }
    }

    // MARK: Root

    private var root: some View {
        VStack(spacing: 12) {
            RowGroup {
                SheetRow(title: "Provider", value: providerLabel, chevron: true) {
                    page = .providers
                }
                RowDivider()
                SheetRow(title: "Model", value: modelLabel, chevron: true) { page = .models }
                RowDivider()
                SheetRow(title: "Thinking", value: thinkingLabel, chevron: true) {
                    page = .thinking
                }
                RowDivider()
                SheetRow(title: "Mode", value: modeLabel, chevron: true) { page = .modes }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Pages

    private var providerPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                if providers.isEmpty {
                    providerEmptyState
                } else {
                    RowGroup {
                        ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                            SheetRow(
                                title: provider.label ?? provider.provider,
                                detail: providerDetail(provider),
                                checked: draft.providerId == provider.provider,
                                badge: providerBadge(provider)
                            ) {
                                guard provider.isAvailable else { return }
                                Haptics.selection()
                                draft.selectProvider(provider.provider, catalog: catalog)
                                page = .root
                            }
                            if index < providers.count - 1 { RowDivider() }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    /// Every enabled provider, in the daemon's order; one that is still probing says so and fills
    /// in through `providers_snapshot_update`. Only a ready one can be picked.
    @ViewBuilder private var providerEmptyState: some View {
        switch catalog.phase {
        case .loading, .idle:
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
        case .failed(let message):
            Text(message)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.failureInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        case .ready:
            Text("No enabled providers on this host.")
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
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
        ScrollView {
            VStack(spacing: 12) {
                if models.isEmpty {
                    VStack(spacing: 8) {
                        if catalog.provider(draft.providerId ?? "")?.status == .loading {
                            ProgressView().controlSize(.small)
                        }
                        Text(
                            catalog.provider(draft.providerId ?? "")?.status == .loading
                                ? "Loading models from this provider…"
                                : "No models reported by this provider"
                        )
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                    }
                    .padding(.top, 24)
                } else {
                    RowGroup {
                        ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                            SheetRow(
                                title: model.label,
                                detail: model.description,
                                checked: draft.modelId == model.id,
                                badge: model.isDefault == true ? "Default" : nil
                            ) {
                                Haptics.selection()
                                draft.selectModel(model.id, catalog: catalog)
                                page = .root
                            }
                            if index < models.count - 1 { RowDivider() }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    /// One row per level, in the provider's order, the current one checked (§4.2). "Default" means
    /// the provider's own choice for this model, which the create request leaves out.
    private var thinkingPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                RowGroup {
                    SheetRow(
                        title: "Default", detail: "Use the provider's level for this model",
                        checked: draft.thinkingOptionId == nil
                    ) {
                        Haptics.selection()
                        draft.selectThinking(nil)
                        page = .root
                    }
                    ForEach(thinkingOptions) { option in
                        RowDivider()
                        SheetRow(
                            title: option.label, detail: option.description,
                            checked: draft.thinkingOptionId == option.id,
                            badge: option.isDefault == true ? "Default" : nil
                        ) {
                            Haptics.selection()
                            draft.selectThinking(option.id)
                            page = .root
                        }
                    }
                }
                .padding(.horizontal, 16)
                if thinkingOptions.isEmpty {
                    Text(
                        catalog.provider(draft.providerId ?? "")?.status == .loading
                            ? "Waiting for this provider's model list…"
                            : "This model reports no thinking levels."
                    )
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var modePage: some View {
        ScrollView {
            VStack(spacing: 12) {
                RowGroup {
                    ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                        SheetRow(
                            title: mode.label, detail: mode.description,
                            checked: draft.modeId == mode.id
                        ) {
                            Haptics.selection()
                            draft.selectMode(mode.id)
                            page = .root
                        }
                        if index < modes.count - 1 { RowDivider() }
                    }
                }
                .padding(.horizontal, 16)
                if modes.isEmpty {
                    Text("This provider reports no modes.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: Labels

    private var providerLabel: String {
        guard let providerId = draft.providerId else { return "Select" }
        return catalog.provider(providerId)?.label ?? providerId
    }

    private var modelLabel: String {
        guard let modelId = draft.modelId else { return "Select" }
        return models.first(where: { $0.id == modelId })?.label ?? modelId
    }

    private var thinkingLabel: String {
        guard let id = draft.thinkingOptionId else { return "Default" }
        return thinkingOptions.first(where: { $0.id == id })?.label ?? id
    }

    private var modeLabel: String {
        guard let id = draft.modeId else { return "Default" }
        return modes.first(where: { $0.id == id })?.label ?? id
    }
}
#endif
