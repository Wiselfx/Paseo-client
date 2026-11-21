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
    /// Bumped by every pick; drives the selection haptic.
    @State private var selectionCount = 0

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
            switch page {
            case .root:
                // Scrolls so the last rows stay reachable at large text sizes.
                ScrollView {
                    RowGroup {
                        ListRow(title: "Provider", accessory: .value(providerLabel)) {
                            page = .providers
                        }
                        RowDivider()
                        ListRow(title: "Model", accessory: .value(modelLabel)) { page = .models }
                        RowDivider()
                        ListRow(title: "Thinking", accessory: .value(thinkingLabel)) {
                            page = .thinking
                        }
                        RowDivider()
                        ListRow(title: "Mode", accessory: .value(modeLabel)) { page = .modes }
                    }
                    .padding(.horizontal, 16)
                }
            case .providers:
                DraftProviderPage(
                    providers: providers, selectedId: draft.providerId, phase: catalog.phase,
                    onSelect: { provider in
                        selectionCount += 1
                        draft.selectProvider(provider.provider, catalog: catalog)
                        page = .root
                    })
            case .models:
                DraftModelPage(
                    models: models, selectedId: draft.modelId, isLoading: providerIsLoading,
                    onSelect: { id in
                        selectionCount += 1
                        draft.selectModel(id, catalog: catalog)
                        page = .root
                    })
            case .thinking:
                DraftThinkingPage(
                    options: thinkingOptions, selectedId: draft.thinkingOptionId,
                    isLoading: providerIsLoading,
                    onSelect: { id in
                        selectionCount += 1
                        draft.selectThinking(id)
                        page = .root
                    })
            case .modes:
                DraftModePage(
                    modes: modes, selectedId: draft.modeId,
                    onSelect: { id in
                        selectionCount += 1
                        draft.selectMode(id)
                        page = .root
                    })
            }
            Spacer(minLength: 0)
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.height(430), .large])
        .presentationDragIndicator(.visible)
        .paseoFeedback(.selection, trigger: selectionCount)
        .task {
            // The draft's sheet can open before the conversation ever asked for a catalogue.
            if catalog.providers.isEmpty {
                let cwd = draft.cwd
                await catalog.loadCatalog(cwd: cwd.isEmpty ? nil : cwd)
            }
        }
    }

    /// The chosen provider is still probing, so an empty model or thinking list may yet fill in.
    private var providerIsLoading: Bool {
        catalog.provider(draft.providerId ?? "")?.status == .loading
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
