#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// General → Chat: transcript display, reasoning expansion and the send-while-running behaviour.
struct GeneralChatSection: View {
    /// M8c: what tap does on send while a turn is running (steer | queue | interrupt).
    @AppStorage(DefaultSendBehavior.storageKey) private var defaultSend = DefaultSendBehavior.steer.rawValue
    /// M7f: Full / Collapse tool calls / Collapse turns.
    @AppStorage(ChatDisplayMode.storageKey) private var chatDisplay = ChatDisplayMode.full.rawValue
    @AppStorage("paseo.reasoning.alwaysExpand") private var alwaysExpandReasoning = false

    private var defaultSendBehavior: DefaultSendBehavior {
        DefaultSendBehavior(rawValue: defaultSend) ?? .steer
    }

    private var chatDisplayMode: ChatDisplayMode {
        ChatDisplayMode(rawValue: chatDisplay) ?? .full
    }

    var body: some View {
        Section {
            SettingsMenuRow("Chat display", value: chatDisplayMode.label) {
                Picker("Chat display", selection: $chatDisplay) {
                    ForEach(ChatDisplayMode.allCases, id: \.self) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
            .accessibilityIdentifier("settings.chatDisplay")
            .paseoFeedback(.selection, trigger: chatDisplay)
            ListRow(
                title: "Always expand reasoning",
                accessory: ListRow.Accessory.toggle($alwaysExpandReasoning)
            )
            .panelRow()
            .accessibilityIdentifier("settings.alwaysExpandReasoning")
            SettingsMenuRow("When the agent is running", value: defaultSendBehavior.label) {
                Picker("When the agent is running", selection: $defaultSend) {
                    ForEach(DefaultSendBehavior.allCases, id: \.self) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
            .accessibilityIdentifier("settings.defaultsend")
            .paseoFeedback(.selection, trigger: defaultSend)
        } header: {
            Text("Chat")
        } footer: {
            Text(
                "Applies when you tap send while a turn is running. Long-press on send does the opposite between Steer and Queue."
            )
        }
    }
}
#endif
