#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// General → Privacy: whether agent names appear on the Lock Screen and system surfaces.
struct GeneralPrivacySection: View {
    /// G16: agent names on the Lock Screen and system surfaces. Off by default.
    @AppStorage(PaseoSettingsKeys.showAgentNames) private var showAgentNames = false

    var body: some View {
        Section {
            ListRow(title: "Show agent names", systemImage: "person", accessory: ListRow.Accessory.toggle($showAgentNames))
                .panelRow()
                .accessibilityIdentifier("settings.privacy.showAgentNames")
        } header: {
            Text("Privacy")
        } footer: {
            Text(
                "With this off, the Lock Screen and system surfaces say \"Agent\" instead of naming your chats. In-app search still finds chats by name: that index never leaves this phone."
            )
        }
    }
}
#endif
