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
        Task { await hostSettings.save(patch) }
    }
}
#endif
