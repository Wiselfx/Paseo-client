#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → Host → Workspaces: whether clean Paseo workspaces are archived once their pull
/// request merges.
struct WorkspacesPage: View {
    let session: HostSession

    private var hostSettings: HostSettingsStore { session.hostSettings }

    var body: some View {
        PageList {
            Section {
                ListRow(
                    title: "Auto-archive after merge",
                    subtitle:
                        "Automatically archive clean Paseo workspaces after their pull request is merged",
                    accessory: ListRow.Accessory.toggle(
                        configBinding(
                            get: { $0.autoArchiveAfterMerge },
                            set: { $0.autoArchiveAfterMerge = $1 }))
                )
                .panelRow()
                .disabled(hostSettings.isSaving || hostSettings.config == nil)
                .accessibilityIdentifier("settings.config.Auto-archive after merge")
            } header: {
                Text("Workspaces")
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
        .inlinePageTitle("Workspaces")
        .refreshable { await hostSettings.load() }
    }

    private func configBinding(
        get: @escaping (DaemonConfig) -> Bool,
        set: @escaping (inout DaemonConfigPatch, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard let config = hostSettings.config else { return false }
                return get(config)
            },
            set: { newValue in
                var patch = DaemonConfigPatch()
                set(&patch, newValue)
                Haptics.selection()
                Task { await hostSettings.save(patch) }
            })
    }
}
#endif
