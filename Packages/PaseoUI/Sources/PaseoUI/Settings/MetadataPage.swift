#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → Host → Metadata: automatic or manual generation, and the model used for it.
/// Manual pushes the model picker, so back returns here (audit C #10).
struct MetadataPage: View {
    let session: HostSession

    private var hostSettings: HostSettingsStore { session.hostSettings }

    private var isAutomatic: Bool {
        session.hostSettings.config?.metadataGeneration?.providers.isEmpty ?? true
    }

    private var configuredProviders: [DaemonConfig.StructuredGenerationProvider] {
        session.hostSettings.config?.metadataGeneration?.providers ?? []
    }

    private var modelLabel: String {
        guard let first = configuredProviders.first else { return "Choose a model…" }
        if let model = first.model, !model.isEmpty { return "\(first.provider) / \(model)" }
        return "\(first.provider) / provider default"
    }

    var body: some View {
        PageList {
            Section {
                ListRow(
                    title: "Model selection",
                    accessory: ListRow.Accessory.value(isAutomatic ? "Automatic" : "Manual")
                )
                .panelRow()
                modeRow
                    .panelRow()
            } header: {
                Text("Metadata generation")
            } footer: {
                Text(
                    "Used for titles, branch names, commit messages and pull requests drafted by the host."
                )
            }
            if !isAutomatic {
                Section {
                    PageLink(
                        SettingsRoute.metadataModel,
                        title: "Model",
                        subtitle: modelLabel
                    )
                    .accessibilityIdentifier("settings.metadata.model")
                } header: {
                    Text("Model")
                }
            }
            if let error = hostSettings.error {
                Section {
                    InlineBanner(
                        .failure, title: error,
                        action: ("Try again", { Task { await hostSettings.load() } }))
                        .panelRow(Palette.background)
                }
            }
        }
        .inlinePageTitle("Metadata")
        .refreshable { await hostSettings.load() }
    }

    /// The two modes: Automatic writes an empty provider list; Manual pushes the model picker,
    /// and the mode flips when a model is chosen (the pre-refactor behaviour).
    private var modeRow: some View {
        HStack(spacing: Space.sm) {
            Button {
                Haptics.selection()
                save { $0.metadataGeneration = .init(providers: []) }
            } label: {
                chipLabel("Automatic", isSelected: isAutomatic)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.metadata.mode.Automatic")
            .accessibilityAddTraits(isAutomatic ? .isSelected : [])
            .disabled(hostSettings.config == nil || hostSettings.isSaving)
            NavigationLink(value: SettingsRoute.metadataModel) {
                chipLabel("Manual", isSelected: !isAutomatic)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.metadata.mode.Manual")
            .accessibilityAddTraits(isAutomatic ? [] : .isSelected)
            .disabled(hostSettings.config == nil || hostSettings.isSaving)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
    }

    private func chipLabel(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.paseo(.callout, weight: .semibold))
            .foregroundStyle(isSelected ? Palette.background : Palette.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: 40)
            .background(isSelected ? Palette.ink : Palette.chip, in: .capsule)
    }

    private func save(_ build: (inout DaemonConfigPatch) -> Void) {
        var patch = DaemonConfigPatch()
        build(&patch)
        Haptics.selection()
        Task { await hostSettings.save(patch) }
    }
}

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
