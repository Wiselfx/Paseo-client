#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Provider detail: the config-owned custom models, with add and remove. Owns the new-model
/// field and its error, so typing here does not re-evaluate the diagnostic and discovered lists.
struct CustomModelsSection: View {
    let session: HostSession
    let providerID: String

    @State private var newModelID = ""
    @State private var modelError: String?

    private var customModels: [DaemonProviderModel] {
        session.hostSettings.additionalModels(for: providerID)
    }
    private var discoveredModels: [AgentModelDefinition] {
        session.agentControl.provider(providerID)?.models ?? []
    }

    var body: some View {
        SettingsSectionLabel(title: "Custom")
        RowGroup {
            if customModels.isEmpty {
                Text("No custom models. Add one below.")
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.lg)
                    .frame(minHeight: 52)
            } else {
                ForEach(customModels.enumerated(), id: \.element.id) { index, model in
                    CustomModelRow(model: model) { removeCustomModel(model) }
                    if index < customModels.count - 1 { RowDivider() }
                }
            }
            RowDivider()
            AddCustomModelRow(modelID: $newModelID) { addCustomModel() }
        }
        if let modelError {
            InlineBanner(.failure, title: modelError)
                .padding(.horizontal, Space.lg)
        }
        Text("Custom models live in the host's config, merged into this provider's catalogue.")
            .font(.paseo(.footnote))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, Space.lg)
    }

    // MARK: Add / remove custom models

    private func addCustomModel() {
        let trimmed = newModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            modelError = "Enter a model ID."
            return
        }
        if customModels.contains(where: { $0.id == trimmed })
            || discoveredModels.contains(where: { $0.id == trimmed }) {
            modelError = "A model with that ID already exists."
            return
        }
        modelError = nil
        newModelID = ""
        setCustomModels(customModels + [DaemonProviderModel(id: trimmed, label: trimmed)])
    }

    private func removeCustomModel(_ model: DaemonProviderModel) {
        modelError = nil
        setCustomModels(customModels.filter { $0.id != model.id })
    }

    /// Writes the whole `additionalModels` array for this provider (a per-provider merge, like
    /// the enable switch), then asks the daemon to re-probe so the catalogue picks it up.
    private func setCustomModels(_ next: [DaemonProviderModel]) {
        var patch = DaemonConfigPatch()
        patch.providers = [providerID: .init(additionalModels: next)]
        Task {
            let ok = await session.hostSettings.save(patch)
            if ok {
                await session.agentControl.refreshCatalog()
            } else {
                modelError = session.hostSettings.error ?? "The host rejected that change."
            }
        }
    }
}
#endif
