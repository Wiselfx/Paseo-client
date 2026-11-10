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
    private var kindModels: [LocalSpeechModel] { voice.models(kind: siteID.kind) }
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
        VStack(spacing: 0) {
            SheetHeader(title: title, close: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
                        .padding(.horizontal, 16)
                        .frame(height: 60)
                        .accessibilityIdentifier("settings.voice.provider")
                        if let hint = setByHint(fields[.provider]) {
                            Text(hint)
                                .font(.paseo(.footnote))
                                .foregroundStyle(Palette.secondaryInk)
                                .padding(.leading, 16)
                        }
                    }
                    .disabled(fields[.provider]?.readOnly == true)

                    switch provider {
                    case .local:
                        localSection
                    case .openai:
                        openAISection
                    case .unknown:
                        // The page never opens a sheet for an unknown provider; unreachable.
                        EmptyView()
                    }

                    if let saveError {
                        Text(saveError)
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.failureInk)
                            .padding(.leading, 16)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await voice.loadModels()
        }
        .onDisappear {
            voice.stopModelPolling()
            apiKey = ""
        }
        .confirmationDialog(
            pendingDelete.map { "Delete \($0.label)?" } ?? "Delete model?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let model = pendingDelete else { return }
                pendingDelete = nil
                Task { _ = await voice.delete(modelId: model.id) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            if let model = pendingDelete {
                Text("This frees \(formatModelSize(bytes: model.downloadSizeBytes)). You can download it again later.")
            }
        }
    }

    // MARK: Local

    @ViewBuilder private var localSection: some View {
        if siteID.kind == .stt {
            RowGroup {
                languageField
            }
        }
        sectionLabel("Models")
        RowGroup {
            if kindModels.isEmpty {
                if let error = voice.modelsError {
                    HStack {
                        Text("Couldn't load local models")
                            .font(.paseo(.callout))
                            .foregroundStyle(Palette.secondaryInk)
                        Spacer(minLength: 8)
                        Button("Retry") {
                            Haptics.selection()
                            Task { await voice.loadModels() }
                        }
                        .font(.paseo(.callout, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    Text(error)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                        .padding(.leading, 16)
                } else {
                    Text(voice.modelsPhase == .loading ? "Loading models..." : "No models available")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                }
            } else {
                ForEach(Array(kindModels.enumerated()), id: \.element.id) { index, model in
                    localModelRow(model)
                    if index < kindModels.count - 1 { RowDivider() }
                }
            }
        }
    }

    private func localModelRow(_ model: LocalSpeechModel) -> some View {
        let selected = model.id == selectedLocalModelID
        let state = localModelState(of: model)
        let actionError = voice.modelActionErrors[model.id]
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                Haptics.selection()
                if fields[.model]?.readOnly != true { localModel = model.id }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(model.label)
                                .font(.paseo(.body))
                                .lineLimit(1)
                            if model.isDefault {
                                Text("Recommended")
                                    .font(.paseo(.caption2, weight: .semibold))
                                    .foregroundStyle(Palette.secondaryInk)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Palette.chip, in: .capsule)
                            }
                        }
                        Text(formatModelSize(bytes: model.downloadSizeBytes))
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.secondaryInk)
                        if state == .installed {
                            Text(model.inUse ? "In use" : "Downloaded")
                                .font(.paseo(.caption2, weight: .semibold))
                                .foregroundStyle(Palette.successInk)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Palette.chip, in: .capsule)
                        }
                        if selected, let hint = setByHint(fields[.model]) {
                            Text(hint)
                                .font(.paseo(.footnote))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                    Spacer(minLength: 8)
                    modelControl(model, state: state)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.glyph(.large, weight: .semibold))
                            .foregroundStyle(Palette.selection)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 60)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(fields[.model]?.readOnly == true)
            .accessibilityIdentifier("settings.voice.model." + model.id)
            .accessibilityAddTraits(selected ? .isSelected : [])

            let rowError = actionError ?? failedModelError(state)
            if let rowError {
                Text(rowError)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
                    .padding(.leading, 32)
            }
        }
    }

    private func failedModelError(_ state: LocalModelState) -> String? {
        if case .failed(let error) = state, !error.isEmpty { return error }
        return nil
    }

    private func isFailedModel(_ state: LocalModelState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    @ViewBuilder private func modelControl(_ model: LocalSpeechModel, state: LocalModelState) -> some View {
        switch state {
        case .downloading(let percent):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(percent.map { "Downloading \($0)%" } ?? "Downloading...")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            }
        case .extracting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Extracting...")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            }
        case .installed:
            if !model.inUse {
                Button {
                    Haptics.selection()
                    pendingDelete = model
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.paseo(.footnote, weight: .medium))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.voice.model.delete." + model.id)
            }
        case .failed, .notInstalled:
            Button {
                Haptics.selection()
                Task { _ = await voice.download(modelId: model.id) }
            } label: {
                Label(isFailedModel(state) ? "Retry" : "Download", systemImage: "arrow.down.circle")
                    .font(.paseo(.footnote, weight: .medium))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("settings.voice.model.download." + model.id)
        }
    }

    // MARK: OpenAI

    @ViewBuilder private var openAISection: some View {
        RowGroup {
            fieldColumn(
                title: "API key",
                hint: "Saved on the host and never shown again.",
                envHint: setByHint(fields[.apiKey])) {
                SecureField(
                    "", text: $apiKey,
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
            fieldColumn(
                title: "Base URL",
                hint: "For OpenAI-compatible servers. Leave empty to use OpenAI.",
                envHint: setByHint(fields[.baseUrl])) {
                TextField(
                    "", text: $baseUrl,
                    prompt: Text("https://api.openai.com/v1")
                        .foregroundStyle(Palette.secondaryInk))
                    .font(.paseo(.body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
            .accessibilityIdentifier("settings.voice.openai.baseUrl")
            RowDivider()
            menuRow("Model", options: openAIModelOptions(kind: siteID.kind, selected: openAiModel)) { openAiModel = $0 }
                .disabled(fields[.model]?.readOnly == true)
            if siteID.kind == .stt {
                RowDivider()
                languageField
            } else {
                RowDivider()
                menuRow("Voice", options: openAIVoiceOptions(selected: voiceName)) { voiceName = $0 }
                    .disabled(fields[.voice]?.readOnly == true)
            }
        }
    }

    @ViewBuilder private var languageField: some View {
        fieldColumn(
            title: "Language",
            hint: nil,
            envHint: setByHint(fields[.language])) {
            TextField(
                "", text: $language,
                prompt: Text("Auto-detect").foregroundStyle(Palette.secondaryInk))
                .font(.paseo(.body))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
        }
        .disabled(fields[.language]?.readOnly == true)
        .accessibilityIdentifier("settings.voice.language")
    }

    // MARK: Footer + save

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.paseo(.callout, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .disabled(saving)
                .accessibilityIdentifier("settings.voice.cancel")
            Spacer()
            Button {
                Haptics.selection()
                save()
            } label: {
                Text(saving ? "Saving…" : "Save")
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 44)
                    .background(Palette.ink, in: .capsule)
                    .opacity(isChanged && !saving ? 1 : 0.5)
            }
            .disabled(!isChanged || saving)
            .accessibilityIdentifier("settings.voice.save")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider() }
    }

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

    // MARK: Shared bits

    @ViewBuilder private func fieldColumn<Content: View>(
        title: String, hint: String?, envHint: String?, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.paseo(.body))
            content()
            if let hint = envHint ?? hint {
                Text(hint)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60, alignment: .leading)
    }

    private func menuRow(
        _ title: String, options: [SpeechModelOption], onSelect: @escaping (String) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.paseo(.body))
            Spacer(minLength: 8)
            Menu {
                ForEach(options, id: \.value) { option in
                    Button {
                        Haptics.selection()
                        onSelect(option.value)
                    } label: {
                        Label(
                            option.label,
                            systemImage: option.value == currentMenuValue(options: options, title: title)
                                ? "checkmark" : "circle")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(currentMenuValue(options: options, title: title))
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .accessibilityLabel("\(title), currently \(currentMenuValue(options: options, title: title))")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func currentMenuValue(options: [SpeechModelOption], title: String) -> String {
        if title == "Model" { return openAiModel }
        if title == "Voice" { return voiceName }
        return options.first?.value ?? ""
    }

    /// "Set by …" when an env var decides the field.
    private func setByHint(_ source: SpeechFieldSource?) -> String? {
        guard let envVar = source?.envVar else { return nil }
        return "Set by \(envVar)"
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.paseo(.callout))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }
}
#endif
