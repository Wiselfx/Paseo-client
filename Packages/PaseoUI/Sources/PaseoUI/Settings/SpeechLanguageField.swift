#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The speech-to-text language field. Read-only when an env var decides the language.
struct SpeechLanguageField: View {
    @Binding var language: String
    let source: SpeechFieldSource?

    var body: some View {
        SpeechFieldColumn(
            title: "Language",
            hint: nil,
            envHint: source?.setByHint) {
            TextField(
                "Language", text: $language,
                prompt: Text("Auto-detect").foregroundStyle(Palette.secondaryInk))
                .font(.paseo(.body))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
        }
        .disabled(source?.readOnly == true)
        .accessibilityIdentifier("settings.voice.language")
    }
}
#endif
