#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// General → Fonts: the content and code size menus. Each menu is an inline `Picker`, so the
/// system draws the checkmark and VoiceOver announces the selected option.
struct GeneralFontsSection: View {
    @AppStorage(ClaudeTextScale.contentStorageKey) private var contentTextSize =
        ClaudeTextScale.Content.medium.rawValue
    @AppStorage(ClaudeTextScale.codeStorageKey) private var codeFontSize =
        ClaudeTextScale.Code.medium.rawValue

    var body: some View {
        Section {
            SettingsMenuRow("Content size", value: contentTextSize) {
                Picker("Content size", selection: $contentTextSize) {
                    ForEach(ClaudeTextScale.Content.allCases, id: \.rawValue) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
            .accessibilityIdentifier("settings.fonts.content")
            .paseoFeedback(.selection, trigger: contentTextSize)
            SettingsMenuRow("Code size", value: codeFontSize) {
                Picker("Code size", selection: $codeFontSize) {
                    ForEach(ClaudeTextScale.Code.allCases, id: \.rawValue) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
            .accessibilityIdentifier("settings.fonts.code")
            .paseoFeedback(.selection, trigger: codeFontSize)
        } header: {
            Text("Fonts")
        } footer: {
            Text(
                "Content size scales prose and headings on top of Dynamic Type; code size scales code blocks, diffs and tool output. Applies live."
            )
        }
    }
}
#endif
