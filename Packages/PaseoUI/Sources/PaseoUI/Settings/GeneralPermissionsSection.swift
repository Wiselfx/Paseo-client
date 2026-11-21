#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// General → Permissions: Allow/Deny buttons on permission notifications.
struct GeneralPermissionsSection: View {
    /// G19: Allow/Deny buttons on permission notifications. Off by default.
    @AppStorage(PaseoSettingsKeys.notificationActions) private var notificationActions = false

    var body: some View {
        Section {
            ListRow(title: "Allow and deny from notifications", systemImage: "checkmark.circle", accessory: ListRow.Accessory.toggle($notificationActions))
                .panelRow()
                .accessibilityIdentifier("settings.notifications.actions")
        } header: {
            Text("Permissions")
        } footer: {
            Text(
                "With this on, simple permission requests offer Allow and Deny buttons right on the notification. Answering needs the phone unlocked. Anything richer stays in the chat."
            )
        }
    }
}
#endif
