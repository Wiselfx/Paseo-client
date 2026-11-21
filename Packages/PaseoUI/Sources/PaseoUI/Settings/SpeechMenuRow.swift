#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// A title and the current value as a menu button (OpenAI model, voice). The menu holds an
/// inline `Picker`, so the system marks the selected option and VoiceOver announces it.
struct SpeechMenuRow: View {
    let title: String
    let options: [SpeechModelOption]
    @Binding var selection: String

    var body: some View {
        HStack {
            Text(title)
                .font(.paseo(.body))
            Spacer(minLength: Space.sm)
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 5) {
                    Text(selection)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .accessibilityLabel("\(title), currently \(selection)")
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: 52)
        .paseoFeedback(.selection, trigger: selection)
    }
}
#endif
