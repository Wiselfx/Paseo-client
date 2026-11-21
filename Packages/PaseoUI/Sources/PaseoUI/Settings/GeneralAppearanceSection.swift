#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// General → Appearance: the light/dark picker and the accent. Owns only the accent key, so the
/// other sections do not re-evaluate when it changes.
struct GeneralAppearanceSection: View {
    @AppStorage(ClaudeAccent.storageKey) private var accent = ClaudeAccent.paseo.rawValue

    var body: some View {
        Section {
            AppearancePicker()
                .padding(Space.lg)
                .panelRow()
            HStack(spacing: Space.md) {
                Text("Accent")
                    .font(.paseo(.body))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Space.sm)
                Picker("Accent", selection: $accent) {
                    ForEach(ClaudeAccent.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 172)
                .paseoFeedback(.selection, trigger: accent)
                .accessibilityIdentifier("settings.accent")
            }
            .padding(.horizontal, Space.lg)
            .frame(minHeight: 44)
            .panelRow()
        } header: {
            Text("Appearance")
        }
    }
}
#endif
