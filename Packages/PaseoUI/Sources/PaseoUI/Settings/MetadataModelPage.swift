#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → Host → Metadata → Model: the catalogue's providers and their models, one tap to
/// choose. Choosing pops back to the Metadata page.
struct MetadataModelPage: View {
    let session: HostSession

    @Environment(\.dismiss) private var dismiss

    private var catalog: AgentControlStore { session.agentControl }

    private var configuredProviders: [DaemonConfig.StructuredGenerationProvider] {
        session.hostSettings.config?.metadataGeneration?.providers ?? []
    }

    var body: some View {
        PageList {
            if catalog.phase == .loading, catalog.providers.isEmpty {
                Section {
                    LoadingState("Loading providers…")
                        .frame(height: 120)
                        .panelRow(Palette.background)
                }
            } else if catalog.readyProviders.isEmpty {
                Section {
                    EmptyState(
                        title: "No usable models on this host",
                        message: "Enable a provider on the Providers page first."
                    )
                    .panelRow(Palette.background)
                }
            } else {
                ForEach(providerModels, id: \.id) { entry in
                    Section {
                        ForEach(entry.models) { model in
                            modelRow(provider: entry.id, model: model)
                        }
                    } header: {
                        Text(entry.label)
                    }
                }
            }
        }
        .inlinePageTitle("Model")
        .refreshable { await catalog.refreshCatalog() }
        .task {
            if catalog.phase == .idle { await catalog.loadCatalog() }
        }
    }

    /// One section per ready provider that actually advertises models.
    private var providerModels: [(id: String, label: String, models: [AgentModelDefinition])] {
        catalog.readyProviders.compactMap { provider in
            let models = catalog.models(forProvider: provider.provider)
            guard !models.isEmpty else { return nil }
            return (id: provider.provider, label: provider.label ?? provider.provider, models: models)
        }
    }

    private func modelRow(provider: String, model: AgentModelDefinition) -> some View {
        let isSelected = isModelSelected(provider: provider, modelId: model.id)
        return ListRow(
            title: model.label,
            subtitle: model.description,
            accessory: isSelected
                ? ListRow.Accessory.checkmark(true)
                : (model.isDefault == true ? ListRow.Accessory.badge("Default") : ListRow.Accessory.none),
            action: {
                Haptics.selection()
                select(provider: provider, modelId: model.id)
            }
        )
        .panelRow()
    }

    private func isModelSelected(provider: String, modelId: String) -> Bool {
        guard let first = configuredProviders.first, first.provider == provider else { return false }
        return first.model == modelId
    }

    private func select(provider: String, modelId: String) {
        let tail = Array(configuredProviders.dropFirst())
        var patch = DaemonConfigPatch()
        patch.metadataGeneration = .init(
            providers: [.init(provider: provider, model: modelId)] + tail)
        Task {
            _ = await session.hostSettings.save(patch)
            dismiss()
        }
    }
}
#endif
