#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → General: appearance, fonts, your name, feedback, notifications and chat display.
/// A local page: everything here is `@AppStorage`, so there is nothing to refresh (PLAN §RE).
struct GeneralPage: View {
    @AppStorage(ClaudeTextScale.contentStorageKey) private var contentTextSize =
        ClaudeTextScale.Content.medium.rawValue
    @AppStorage(ClaudeTextScale.codeStorageKey) private var codeFontSize =
        ClaudeTextScale.Code.medium.rawValue
    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    @AppStorage(PaseoSettingsKeys.haptics) private var haptics = true
    @AppStorage(PaseoSettingsKeys.mascot) private var mascot = true
    /// M10: post local OS notifications when an agent or terminal needs you. On by default.
    @AppStorage(AttentionNotificationKeys.enabled) private var notificationsEnabled = true
    /// M12: attention sound cue level (off | soft | clear), DSH wording. Default off.
    @AppStorage(SoundCueLevel.storageKey) private var soundCueLevel = SoundCueLevel.off.rawValue
    /// M8c: what tap does on send while a turn is running (steer | queue | interrupt).
    @AppStorage(DefaultSendBehavior.storageKey) private var defaultSend = DefaultSendBehavior.steer.rawValue
    /// M7f: Full / Collapse tool calls / Collapse turns.
    @AppStorage(ChatDisplayMode.storageKey) private var chatDisplay = ChatDisplayMode.full.rawValue
    @AppStorage("paseo.reasoning.alwaysExpand") private var alwaysExpandReasoning = false

    @Environment(\.notificationPermissionAction) private var requestNotificationPermission
    @Environment(\.notificationTestAction) private var notificationTestAction
    @State private var isSendingTestNotification = false
    @State private var testNotificationSent: Bool?

    private var defaultSendBehavior: DefaultSendBehavior {
        DefaultSendBehavior(rawValue: defaultSend) ?? .steer
    }

    private var chatDisplayMode: ChatDisplayMode {
        ChatDisplayMode(rawValue: chatDisplay) ?? .full
    }

    /// Upstream `settings.notifications.testHint` / `permissionRequired` (en.ts:2383-2384),
    /// keyed on the notifications toggle since PaseoUI cannot read the OS status.
    private var testNotificationHint: String {
        notificationsEnabled
            ? "Send a notification using these settings"
            : "Allow notification access before testing"
    }

    var body: some View {
        PageList {
            Section {
                AppearancePicker()
                    .padding(Space.lg)
                    .panelRow()
            } header: {
                Text("Appearance")
            }
            Section {
                SettingsMenuRow("Content size", value: contentTextSize) {
                    ForEach(ClaudeTextScale.Content.allCases, id: \.rawValue) { option in
                        Button {
                            Haptics.selection()
                            contentTextSize = option.rawValue
                        } label: {
                            Label(
                                option.rawValue,
                                systemImage: contentTextSize == option.rawValue
                                    ? "checkmark" : "circle")
                        }
                    }
                }
                .accessibilityIdentifier("settings.fonts.content")
                SettingsMenuRow("Code size", value: codeFontSize) {
                    ForEach(ClaudeTextScale.Code.allCases, id: \.rawValue) { option in
                        Button {
                            Haptics.selection()
                            codeFontSize = option.rawValue
                        } label: {
                            Label(
                                option.rawValue,
                                systemImage: codeFontSize == option.rawValue
                                    ? "checkmark" : "circle")
                        }
                    }
                }
                .accessibilityIdentifier("settings.fonts.code")
            } header: {
                Text("Fonts")
            } footer: {
                Text(
                    "Content size scales prose and headings on top of Dynamic Type; code size scales code blocks, diffs and tool output. Applies live."
                )
            }
            Section {
                HStack(spacing: Space.sm) {
                    Text("Your name")
                        .font(.paseo(.body))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: Space.sm)
                    TextField("Your name", text: $name)
                        .font(.paseo(.body))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                }
                .padding(.horizontal, Space.lg)
                .frame(minHeight: 44)
                .panelRow()
            } header: {
                Text("You")
            } footer: {
                Text("Used in the greeting on the home screen and the sidebar avatar.")
            }
            Section {
                ListRow(title: "Haptic feedback", systemImage: "iphone.gen3.radiowaves.left.and.right", accessory: ListRow.Accessory.toggle($haptics))
                    .panelRow()
                    .accessibilityIdentifier("settings.haptics")
                    .onChange(of: haptics) { _, enabled in Haptics.setEnabled(enabled) }
                ListRow(title: "Show mascot", systemImage: "sparkles", accessory: ListRow.Accessory.toggle($mascot))
                    .panelRow()
                    .accessibilityIdentifier("settings.mascot")
            } header: {
                Text("Feedback")
            }
            Section {
                ListRow(title: "Agent notifications", systemImage: "bell", accessory: ListRow.Accessory.toggle($notificationsEnabled))
                    .panelRow()
                    .accessibilityIdentifier("settings.notifications.enabled")
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled { requestNotificationPermission() }
                    }
                SettingsMenuRow("Sound cue", value: currentSoundCue.title) {
                    ForEach(SoundCueLevel.allCases, id: \.rawValue) { level in
                        Button {
                            Haptics.selection()
                            soundCueLevel = level.rawValue
                        } label: {
                            Label(
                                level.title,
                                systemImage: soundCueLevel == level.rawValue
                                    ? "checkmark" : "circle")
                        }
                    }
                }
                .accessibilityIdentifier("settings.notifications.soundCue")
                testNotificationRow
            } header: {
                Text("Notifications")
            } footer: {
                Text(
                    "Play a cue when a task finishes or is blocked. Local notifications while Paseo is open or recently backgrounded. True push while the app is closed is not available without a relay."
                )
            }
            Section {
                SettingsMenuRow("Chat display", value: chatDisplayMode.label) {
                    ForEach(ChatDisplayMode.allCases, id: \.self) { option in
                        Button {
                            Haptics.selection()
                            chatDisplay = option.rawValue
                        } label: {
                            Label(
                                option.label,
                                systemImage: chatDisplay == option.rawValue ? "checkmark" : "circle")
                        }
                    }
                }
                .accessibilityIdentifier("settings.chatDisplay")
                ListRow(
                    title: "Always expand reasoning",
                    accessory: ListRow.Accessory.toggle($alwaysExpandReasoning)
                )
                .panelRow()
                .accessibilityIdentifier("settings.alwaysExpandReasoning")
                SettingsMenuRow("When the agent is running", value: defaultSendBehavior.label) {
                    ForEach(DefaultSendBehavior.allCases, id: \.self) { option in
                        Button {
                            Haptics.selection()
                            defaultSend = option.rawValue
                        } label: {
                            Label(
                                option.label,
                                systemImage: defaultSendBehavior == option ? "checkmark" : "circle")
                        }
                    }
                }
                .accessibilityIdentifier("settings.defaultsend")
            } header: {
                Text("Chat")
            } footer: {
                Text(
                    "Applies when you tap send while a turn is running. Long-press on send does the opposite between Steer and Queue."
                )
            }
        }
        .inlinePageTitle("General")
        .alert(
            testNotificationSent == true
                ? "Test notification sent" : "Unable to send test notification",
            isPresented: Binding(
                get: { testNotificationSent != nil },
                set: { if !$0 { testNotificationSent = nil } }))
        {
            Button("OK") { testNotificationSent = nil }
        } message: {
            Text(
                testNotificationSent == true
                    ? "Paseo handed the notification to the operating system."
                    : "Failed to send notification.")
        }
    }

    private var currentSoundCue: SoundCueLevel {
        SoundCueLevel(rawValue: soundCueLevel) ?? .off
    }

    /// The test row: the label, the hint and the chip button. The result is an alert, since it
    /// is not visible on screen.
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
    }

    private func sendTestNotification() {
        guard !isSendingTestNotification else { return }
        isSendingTestNotification = true
        Task {
            let sent = await notificationTestAction()
            isSendingTestNotification = false
            testNotificationSent = sent
        }
    }
}
#endif
