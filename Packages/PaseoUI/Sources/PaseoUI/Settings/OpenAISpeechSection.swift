#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The OpenAI provider's fields: API key, base URL, model and language or voice. The API key is
/// a secret: the field starts empty and a saved key is never shown again.
struct OpenAISpeechSection: View {
    let kind: SpeechModelKind
    let fields: [SpeechProviderField: SpeechFieldSource]
    let hasSavedApiKey: Bool
    @Binding var apiKey: String
    @Binding var baseUrl: String
    @Binding var openAiModel: String
    @Binding var voiceName: String
    @Binding var language: String

    var body: some View {
        RowGroup {
            SpeechFieldColumn(
                title: "API key",
                hint: "Saved on the host and never shown again.",
                envHint: fields[.apiKey]?.setByHint) {
                SecureField(
                    "API key", text: $apiKey,
                    prompt: Text(hasSavedApiKey ? "Saved" : "sk-...")
                        .foregroundStyle(Palette.secondaryInk))
                    .font(.paseo(.body))
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                }
            .accessibilityIdentifier("settings.voice.openai.apiKey")
            RowDivider()
            SpeechFieldColumn(
                title: "Base URL",
                hint: "For OpenAI-compatible servers. Leave empty to use OpenAI.",
                envHint: fields[.baseUrl]?.setByHint) {
                TextField(
                    "Base URL", text: $baseUrl,
                    prompt: Text("https://api.openai.com/v1")
                        .foregroundStyle(Palette.secondaryInk))
                    .font(.paseo(.body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
            .accessibilityIdentifier("settings.voice.openai.baseUrl")
            RowDivider()
            SpeechMenuRow(
                title: "Model",
                options: openAIModelOptions(kind: kind, selected: openAiModel),
                selection: $openAiModel
            )
            .disabled(fields[.model]?.readOnly == true)
            if kind == .stt {
                RowDivider()
                SpeechLanguageField(language: $language, source: fields[.language])
            } else {
                RowDivider()
                SpeechMenuRow(
                    title: "Voice",
                    options: openAIVoiceOptions(selected: voiceName),
                    selection: $voiceName
                )
                .disabled(fields[.voice]?.readOnly == true)
            }
        }
    }
}
#endif
