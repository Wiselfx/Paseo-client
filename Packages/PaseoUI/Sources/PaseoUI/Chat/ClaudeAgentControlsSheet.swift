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

    enum Page: Equatable { case root, models, thinking, modes }

    private var providerId: String? {
        if let id = store.agent?.provider, !id.isEmpty { return id }
        return session.agentControl.readyProviders.first?.provider
    }

    private var models: [AgentModelDefinition] {
        guard let providerId else { return [] }
        return session.agentControl.models(forProvider: providerId)
    }

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
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .onAppear {
            switch session.agentControl.phase {
            case .idle, .failed:
                let cwd = store.agent?.cwd
                Task { await session.agentControl.loadCatalog(cwd: cwd) }
            case .loading, .ready:
                break
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch session.agentControl.phase {
        case .loading where session.agentControl.providers.isEmpty:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
        case .failed(let message):
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
            }
        }
    }

    private var root: some View {
        VStack(spacing: 12) {
            RowGroup {
                SheetRow(
                    title: "Model", symbol: "cpu", detail: providerDetail,
                    value: modelLabel(store.agent?.model), chevron: true
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
            .padding(.horizontal, 16)
        }
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
                    Text("No models reported by this provider")
                        .font(.system(size: 14))
                        .foregroundStyle(ClaudePalette.secondaryInk)
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
                    Text("This model reports no thinking levels.")
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
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
