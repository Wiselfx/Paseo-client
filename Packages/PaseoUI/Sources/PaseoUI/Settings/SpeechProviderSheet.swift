#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One speech site's provider and that provider's settings: the Local model catalog
/// (download/delete, sizes, recommended) or the OpenAI fields (API key, base URL, model,
/// language or voice). Mounted fresh by the caller for every open (`voice-page.tsx`
/// upstream); the form seeds from the saved site and only changed fields are patched.
///
/// The API key is a secret: it is only ever written into the patch and never shown after
/// save. The read model carries `hasApiKey` only, and the field starts empty.
struct SpeechProviderSheet: View {
    let session: HostSession
    let siteID: SpeechSiteID

    @Environment(\.dismiss) private var dismiss

    @State private var provider: SpeechProvider
    @State private var localModel: String?
    @State private var apiKey = ""
    @State private var baseUrl: String
    @State private var openAiModel: String
    @State private var language: String
    @State private var voiceName: String
    @State private var saving = false
    @State private var saveError: String?
    @State private var pendingDelete: LocalSpeechModel?

    private let savedSite: SpeechSite
    private let savedProvider: SpeechProvider
    private let savedLocalModel: String?
    private let hasSavedApiKey: Bool
    private let savedBaseUrl: String
    private let savedOpenAiModel: String
    private let savedLanguage: String
    private let savedVoice: String
    private let fields: [SpeechProviderField: SpeechFieldSource]

    init(session: HostSession, siteID: SpeechSiteID) {
        self.session = session
        self.siteID = siteID
        let voiceSettings = session.voiceSettings
        let site = voiceSettings.site(siteID) ?? SpeechSite.defaultLocal
        let savedProvider = site.provider.isKnown ? site.provider : .local
        self.savedSite = site
        self.savedProvider = savedProvider
        self.savedLocalModel = site.provider == .local ? site.model : nil
        self.hasSavedApiKey = site.hasApiKey
        self.savedBaseUrl = site.baseUrl ?? ""
        self.savedOpenAiModel = resolveOpenAIModel(kind: siteID.kind, model: site.model)
        self.savedLanguage = site.language ?? ""
        self.savedVoice = resolveOpenAIVoice(site.voice)
        self.fields = speechFieldSources(siteID: siteID, envOverrides: voiceSettings.envOverrides)
        _provider = State(initialValue: savedProvider)
        _localModel = State(initialValue: nil)
        _baseUrl = State(initialValue: savedBaseUrl)
        _openAiModel = State(initialValue: savedOpenAiModel)
        _language = State(initialValue: savedLanguage)
        _voiceName = State(initialValue: savedVoice)
    }

    private var voice: VoiceSettingsStore { session.voiceSettings }
    private var title: String {
        switch siteID {
        case .dictationSTT: "Speech-to-text"
        case .voiceModeSTT: "Listening"
        case .voiceModeTTS: "Speaking"
        }
    }
    private var selectedLocalModelID: String? {
        localModel ?? resolveLocalModel(kind: siteID.kind, model: savedLocalModel, models: voice.models)?.id
    }

    private enum ChangedOpenAIField { case baseUrl, model, voice }

    private var changedOpenAIFields: [ChangedOpenAIField] {
        var changed: [ChangedOpenAIField] = []
        if baseUrl.trimmingCharacters(in: .whitespacesAndNewlines) != savedBaseUrl { changed.append(.baseUrl) }
        if openAiModel != savedOpenAiModel { changed.append(.model) }
        if siteID.kind == .tts, voiceName != savedVoice { changed.append(.voice) }
        return changed
    }

    /// Whether Save has anything to write (same rule as upstream's form `isChanged`).
    private var isChanged: Bool {
        if provider != savedProvider { return true }
        if siteID.kind == .stt,
            language.trimmingCharacters(in: .whitespacesAndNewlines) != savedLanguage { return true }
        if provider == .local { return localModel != nil && localModel != savedLocalModel }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !changedOpenAIFields.isEmpty
    }

    var body: some View {
        SheetScaffold(
            title,
            detents: .large,
            confirm: SheetConfirm(
                "Save", isEnabled: isChanged, isWorking: saving,
                identifier: "settings.voice.save"
            ) {
                save()
            }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    RowGroup {
                        HStack {
                            Text("Provider")
                                .font(.paseo(.body))
                            Spacer(minLength: 8)
                            Picker("Provider", selection: $provider) {
                                Text("Local").tag(SpeechProvider.local)
                                Text("OpenAI").tag(SpeechProvider.openai)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                        .padding(.horizontal, Space.lg)
                        .frame(minHeight: 60)
                        .accessibilityIdentifier("settings.voice.provider")
                        if let hint = fields[.provider]?.setByHint {
                            Text(hint)
                                .font(.paseo(.footnote))
                                .foregroundStyle(Palette.secondaryInk)
                                .padding(.leading, Space.lg)
                        }
                    }
                    .disabled(fields[.provider]?.readOnly == true)

                    switch provider {
                    case .local:
                        LocalSpeechModelsSection(
                            voice: voice,
                            siteID: siteID,
                            fields: fields,
                            selectedModelID: selectedLocalModelID,
                            language: $language,
                            onSelect: { localModel = $0 },
                            onDelete: { pendingDelete = $0 }
                        )
                    case .openai:
                        OpenAISpeechSection(
                            kind: siteID.kind,
                            fields: fields,
                            hasSavedApiKey: hasSavedApiKey,
                            apiKey: $apiKey,
                            baseUrl: $baseUrl,
                            openAiModel: $openAiModel,
                            voiceName: $voiceName,
                            language: $language
                        )
                    case .unknown:
                        // The page never opens a sheet for an unknown provider; unreachable.
                        EmptyView()
                    }

                    if let saveError {
                        InlineBanner(.failure, title: saveError)
                            .padding(.horizontal, Space.lg)
                    }
                }
                .padding(.bottom, Space.md)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            await voice.loadModels()
        }
        .onDisappear {
            voice.stopModelPolling()
            apiKey = ""
        }
        .confirmationDialog(
            pendingDelete.map { "Delete \($0.label)?" } ?? "Delete model?",
            item: $pendingDelete,
            titleVisibility: .visible
        ) { model in
            Button("Delete", role: .destructive) {
                Task { _ = await voice.delete(modelId: model.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text("This frees \(formatModelSize(bytes: model.downloadSizeBytes)). You can download it again later.")
        }
    }

    // MARK: Footer + save


    private func save() {
        guard isChanged, !saving else { return }
        saving = true
        saveError = nil
        let patch = buildSitePatch()
        Task {
            let ok = await voice.save(siteID: siteID, sitePatch: patch)
            saving = false
            if ok {
                apiKey = ""
                Haptics.success()
                dismiss()
            } else {
                saveError = voice.error ?? session.hostSettings.error ?? "Unable to update voice settings"
            }
        }
    }

    /// Changed fields only, skipping read-only ones — same rules as upstream's form.
    private func buildSitePatch() -> SpeechSitePatch {
        var patch = SpeechSitePatch()
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let languageField = fields[.language]
        let languageChanged = siteID.kind == .stt
            && trimmedLanguage != savedLanguage
            && (provider == savedProvider || !trimmedLanguage.isEmpty)
        if languageChanged, languageField?.readOnly != true {
            patch.language = .some(trimmedLanguage.isEmpty ? nil : trimmedLanguage)
        }
        switch provider {
        case .local:
            patch.provider = .local
            if let localModel, fields[.model]?.readOnly != true {
                patch.model = .some(localModel)
            }
        case .openai:
            patch.provider = .openai
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty { patch.apiKey = .some(trimmedKey) }
            for field in changedOpenAIFields {
                switch field {
                case .baseUrl:
                    if fields[.baseUrl]?.readOnly != true {
                        patch.baseUrl = .some(baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : baseUrl.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                case .model:
                    if fields[.model]?.readOnly != true { patch.model = .some(openAiModel) }
                case .voice:
                    if fields[.voice]?.readOnly != true { patch.voice = .some(voiceName) }
                }
            }
        case .unknown:
            break
        }
        return patch
    }
}
#endif
