#if canImport(UIKit)
import SwiftUI

/// Settings → Chat: the chat surface's own controls.
///
/// **Not wired in this build.** The Settings navigator (`Chat/PaseoSettingsView.swift`) is outside
/// this ticket's file list, so this page is complete but unreachable — wiring it is a few lines
/// (a `chat` case in the settings `Page` enum, a root "Chat" row under App, and the detail
/// switch). The chat-display control shares the General → Chat store-backed setting on purpose:
/// same key, same `ChatDisplayMode` enum, one source of truth.
///
/// "Always expand reasoning" is stored in `paseo.reasoning.alwaysExpand` but is **not applied to
/// the transcript yet**: the reasoning rows default to the newest row's liveness in
/// `Conversation/ChatWorkGroup.swift`, which this ticket may not edit. Captions say so.
struct ChatPage: View {
    /// Shared with Settings → General → Chat. Do not fork.
    @AppStorage(ChatDisplayMode.storageKey) private var chatDisplay = ChatDisplayMode.full.rawValue
    /// Staged, not yet read by the transcript (see the file header).
    @AppStorage("paseo.reasoning.alwaysExpand") private var alwaysExpandReasoning = false

    private let typography = ClaudeTypography()

    private var chatDisplayMode: ChatDisplayMode {
        ChatDisplayMode(rawValue: chatDisplay) ?? .full
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Reasoning")
                RowGroup {
                    Toggle(isOn: $alwaysExpandReasoning) {
                        Label("Always expand reasoning", systemImage: "brain")
                            .font(.system(size: 17))
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("settings.chat.alwaysExpandReasoning")
                }
                Text("Show agent thinking and chain-of-thought blocks fully expanded by default. Not applied to the transcript yet — wiring pending.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.leading, 16)
                sectionLabel("Display")
                RowGroup {
                    HStack(spacing: 12) {
                        Text("Chat display")
                            .font(.system(size: 17))
                        Spacer(minLength: 8)
                        Menu {
                            ForEach(ChatDisplayMode.allCases, id: \.self) { option in
                                Button {
                                    Haptics.selection()
                                    chatDisplay = option.rawValue
                                } label: {
                                    Label(
                                        option.label,
                                        systemImage: chatDisplay == option.rawValue
                                            ? "checkmark" : "circle")
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(chatDisplayMode.label)
                                    .font(.system(size: 15))
                                    .foregroundStyle(ClaudePalette.secondary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ClaudePalette.secondary)
                            }
                        }
                        .accessibilityLabel("Chat display, currently \(chatDisplayMode.label)")
                        .accessibilityIdentifier("settings.chat.display")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                }
                Text("How much of an agent's work the chat shows.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.leading, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15))
            .foregroundStyle(ClaudePalette.secondary)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }
}
#endif
