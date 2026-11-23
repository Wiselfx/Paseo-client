#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// General → Notifications: the attention toggle, the sound cue and the test row.
struct GeneralNotificationsSection: View {
    /// M10: post local OS notifications when an agent or terminal needs you. On by default.
    @AppStorage(AttentionNotificationKeys.enabled) private var notificationsEnabled = true
    /// M12: attention sound cue level (off | soft | clear), DSH wording. Default off.
    @AppStorage(SoundCueLevel.storageKey) private var soundCueLevel = SoundCueLevel.off.rawValue

    @Environment(\.notificationActions) private var notificationActions
    @State private var isSendingTestNotification = false
    @State private var testNotificationSent: Bool?

    /// Upstream `settings.notifications.testHint` / `permissionRequired` (en.ts:2383-2384),
    /// keyed on the notifications toggle since PaseoUI cannot read the OS status.
    private var testNotificationHint: String {
        notificationsEnabled
            ? "Send a notification using these settings"
            : "Allow notification access before testing"
    }

    private var currentSoundCue: SoundCueLevel {
        SoundCueLevel(rawValue: soundCueLevel) ?? .off
    }

    var body: some View {
        Section {
            ListRow(title: "Agent notifications", systemImage: "bell", accessory: ListRow.Accessory.toggle($notificationsEnabled))
                .panelRow()
                .accessibilityIdentifier("settings.notifications.enabled")
                .onChange(of: notificationsEnabled) { _, enabled in
                    if enabled { notificationActions?.requestPermission() }
                }
            SettingsMenuRow("Sound cue", value: currentSoundCue.title) {
                Picker("Sound cue", selection: $soundCueLevel) {
                    ForEach(SoundCueLevel.allCases, id: \.rawValue) { level in
                        Text(level.title).tag(level.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
            .accessibilityIdentifier("settings.notifications.soundCue")
            .paseoFeedback(.selection, trigger: soundCueLevel)
            testNotificationRow
        } header: {
            Text("Notifications")
        } footer: {
            Text(
                "Play a cue when a task finishes or is blocked. Local notifications while Paseo is open or recently backgrounded. True push while the app is closed is not available without a relay."
            )
        }
    }

    /// The test row: the label, the hint and the chip button. The result is an alert, since it
    /// is not visible on screen. The alert hangs off this row, the control that triggers it.
    private var testNotificationRow: some View {
        HStack(spacing: Space.sm) {
            ListRow(title: "Test notification", subtitle: testNotificationHint)
            Button(isSendingTestNotification ? "Sending..." : "Send") {
                sendTestNotification()
            }
            .buttonStyle(.paseoSecondary)
            .disabled(!notificationsEnabled || isSendingTestNotification)
            .padding(.trailing, Space.lg)
            .accessibilityIdentifier("settings.notifications.test")
        }
        .panelRow()
        .alert(
            testNotificationSent == true
                ? "Test notification sent" : "Unable to send test notification",
            item: $testNotificationSent
        ) { _ in
            Button("OK") { testNotificationSent = nil }
        } message: { sent in
            Text(
                sent
                    ? "Paseo handed the notification to the operating system."
                    : "Couldn't send the notification.")
        }
    }

    private func sendTestNotification() {
        guard !isSendingTestNotification else { return }
        isSendingTestNotification = true
        Task {
            let sent = await notificationActions?.sendTestNotification() ?? false
            isSendingTestNotification = false
            testNotificationSent = sent
        }
    }
}
#endif
