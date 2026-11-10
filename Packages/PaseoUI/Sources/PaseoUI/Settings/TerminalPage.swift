#if canImport(UIKit)
import SwiftUI

/// Settings → Terminal: how much scrollback SwiftTerm keeps, and what tapping a script's service
/// URL does. Read live by `PaseoTerminalView`.
struct TerminalPage: View {
    /// Shared with `Workspace/PaseoTerminalView.swift`. Default 2,000 lines.
    @AppStorage("paseo.terminal.scrollback") private var scrollback = 2_000
    /// Shared with `Workspace/WorkspaceTerminalsView.swift`. Default `ask` (upstream).
    @AppStorage(ServiceUrlBehavior.storageKey) private var serviceUrlBehavior = ServiceUrlBehavior.ask.rawValue

    private let options: [(label: String, value: Int)] = [
        ("1,000 lines", 1_000),
        ("2,000 lines", 2_000),
        ("5,000 lines", 5_000),
        ("10,000 lines", 10_000),
    ]

    private var selectedLabel: String {
        options.first { $0.value == scrollback }?.label ?? "2,000 lines"
    }

    private var currentBehavior: ServiceUrlBehavior {
        ServiceUrlBehavior(rawValue: serviceUrlBehavior) ?? .ask
    }

    var body: some View {
        SettingsList {
            Section {
                SettingsMenuRow("Scrollback", value: selectedLabel) {
                    ForEach(options, id: \.value) { option in
                        Button {
                            Haptics.selection()
                            scrollback = option.value
                        } label: {
                            Label(
                                option.label,
                                systemImage: scrollback == option.value ? "checkmark" : "circle")
                        }
                    }
                }
                .accessibilityIdentifier("settings.terminal.scrollback")
                SettingsMenuRow(
                    "Clicking a script's service URL", value: currentBehavior.label
                ) {
                    ForEach(ServiceUrlBehavior.allCases, id: \.self) { option in
                        Button {
                            Haptics.selection()
                            serviceUrlBehavior = option.rawValue
                        } label: {
                            Label(
                                option.label,
                                systemImage: currentBehavior == option ? "checkmark" : "circle")
                        }
                    }
                }
                .accessibilityIdentifier("settings.terminal.serviceUrls")
            } header: {
                Text("Terminal")
            } footer: {
                Text("Applies to new and already-open terminal views on this device.")
            }
        }
        .settingsPage("Terminal")
    }
}
#endif
