#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The Local provider's body: the language field (speech-to-text only) and the model catalog.
struct LocalSpeechModelsSection: View {
    let voice: VoiceSettingsStore
    let siteID: SpeechSiteID
    let fields: [SpeechProviderField: SpeechFieldSource]
    let selectedModelID: String?
    @Binding var language: String
    let onSelect: (String) -> Void
    let onDelete: (LocalSpeechModel) -> Void

    private var kindModels: [LocalSpeechModel] { voice.models(kind: siteID.kind) }

    var body: some View {
        if siteID.kind == .stt {
            RowGroup {
                SpeechLanguageField(language: $language, source: fields[.language])
            }
        }
        SettingsSectionLabel(title: "Models")
        RowGroup {
            if kindModels.isEmpty {
                if let error = voice.modelsError {
                    HStack {
                        Text("Couldn't load local models")
                            .font(.paseo(.callout))
                            .foregroundStyle(Palette.secondaryInk)
                        Spacer(minLength: Space.sm)
                        Button("Try again") {
                            Task { await voice.loadModels() }
                        }
                        .font(.paseo(.callout, weight: .semibold))
                    }
                    .padding(.horizontal, Space.lg)
                    .frame(minHeight: 52)
                    Text(error)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                        .padding(.leading, Space.lg)
                } else {
                    Text(voice.modelsPhase == .loading ? "Loading models..." : "No models available")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, Space.lg)
                        .frame(minHeight: 52)
                }
            } else {
                ForEach(kindModels.enumerated(), id: \.element.id) { index, model in
                    LocalSpeechModelRow(
                        model: model,
                        selected: model.id == selectedModelID,
                        state: localModelState(of: model),
                        actionError: voice.modelActionErrors[model.id],
                        setByHint: fields[.model]?.setByHint,
                        isReadOnly: fields[.model]?.readOnly == true,
                        onSelect: { onSelect(model.id) },
                        onDelete: { onDelete(model) },
                        onDownload: { Task { _ = await voice.download(modelId: model.id) } }
                    )
                    if index < kindModels.count - 1 { RowDivider() }
                }
            }
        }
    }
}
#endif
