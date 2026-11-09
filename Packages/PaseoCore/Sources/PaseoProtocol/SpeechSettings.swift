import Foundation

// Host Voice settings and local speech models.
//
// Source: packages/protocol/src/speech/rpc-schemas.ts `SpeechSettingsSchema`,
// `SpeechSettingsPatchSchema`, `LocalSpeechModelSchema`,
// `SpeechLocalModelsListRequestSchema` / `SpeechLocalModelsDownloadRequestSchema` /
// `SpeechLocalModelsDeleteRequestSchema` and their responses; gates listed in
// messages.ts (`features.speechSettings`, added in v0.12.0). The option lists, defaults,
// model states and form rules are a port of the upstream app's voice settings logic
// (`app/screens/settings/voice/voice-settings.ts`, `speech-provider-form.ts`).
//
// The reply-side settings live in `config.features` (`get/set_daemon_config_request`); this
// file decodes that block tolerantly. The read model never carries an OpenAI API key — it
// reports `hasApiKey` only — so a client built on these types cannot echo a secret back.

// MARK: - Providers and sites

/// A speech provider id. Unknown values stay usable rather than failing the whole decode.
public enum SpeechProvider: Sendable, Hashable, Equatable {
    case local
    case openai
    case unknown(String)

    public init(wire: String?) {
        switch wire {
        case "local": self = .local
        case "openai": self = .openai
        case let other?: self = .unknown(other)
        case nil: self = .local
        }
    }

    public var wireValue: String {
        switch self {
        case .local: "local"
        case .openai: "openai"
        case .unknown(let id): id
        }
    }

    public var isKnown: Bool {
        switch self {
        case .local, .openai: true
        case .unknown: false
        }
    }
}

/// Which kind of model a speech site uses on the host (`SpeechModelKind` upstream).
public enum SpeechModelKind: String, Sendable, Hashable, Equatable {
    case stt
    case tts
}

/// The three places that use speech. Each carries its own provider settings in
/// `config.features` under `features.<site>` (`SPEECH_SITE_KIND` upstream).
public enum SpeechSiteID: String, Sendable, Hashable, CaseIterable {
    case dictationSTT = "dictation.stt"
    case voiceModeSTT = "voiceMode.stt"
    case voiceModeTTS = "voiceMode.tts"

    public var kind: SpeechModelKind {
        switch self {
        case .dictationSTT, .voiceModeSTT: .stt
        case .voiceModeTTS: .tts
        }
    }

    /// The `envOverrides` key the daemon names for a field of this site
    /// (`speechSiteFieldPath`, e.g. `features.dictation.stt.model`).
    public func fieldPath(_ field: String) -> String {
        "features.\(rawValue).\(field)"
    }

    /// Stable string for accessibility identifiers (`settings.voice.site.<id>` upstream).
    public var accessibilityID: String { rawValue }
}

// MARK: - Read model

// Source: rpc-schemas.ts `SpeechSttSettingsSchema` / `SpeechTtsSettingsSchema`

/// One speech site's settings as the daemon reports them. `hasApiKey` replaces the secret
/// itself: the wire never returns a saved key. TTS-only fields (`speakerId`, `speed`) and
/// `confidenceThreshold` are decoded but not edited by the settings sheets.
public struct SpeechSite: Decodable, Sendable, Hashable {
    public var provider: SpeechProvider
    public var model: String?
    public var language: String?
    public var hasApiKey: Bool
    public var baseUrl: String?
    public var voice: String?
    public var confidenceThreshold: Double?
    public var speakerId: Int?
    public var speed: Double?

    public init(
        provider: SpeechProvider, model: String? = nil, language: String? = nil,
        hasApiKey: Bool = false, baseUrl: String? = nil, voice: String? = nil,
        confidenceThreshold: Double? = nil, speakerId: Int? = nil, speed: Double? = nil
    ) {
        self.provider = provider
        self.model = model
        self.language = language
        self.hasApiKey = hasApiKey
        self.baseUrl = baseUrl
        self.voice = voice
        self.confidenceThreshold = confidenceThreshold
        self.speakerId = speakerId
        self.speed = speed
    }

    /// The daemon's default site (local provider, no overrides) when the config has none.
    public static var defaultLocal: SpeechSite { SpeechSite(provider: .local) }

    private enum K: String, CodingKey {
        case provider, model, language, hasApiKey, baseUrl, voice, confidenceThreshold, speakerId, speed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        provider = SpeechProvider(wire: try c.decodeIfPresent(String.self, forKey: .provider))
        model = try c.decodeIfPresent(String.self, forKey: .model)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        hasApiKey = try c.decodeIfPresent(Bool.self, forKey: .hasApiKey) ?? false
        baseUrl = try c.decodeIfPresent(String.self, forKey: .baseUrl)
        voice = try c.decodeIfPresent(String.self, forKey: .voice)
        confidenceThreshold = try c.decodeIfPresent(Double.self, forKey: .confidenceThreshold)
        speakerId = try c.decodeIfPresent(Int.self, forKey: .speakerId)
        speed = try c.decodeIfPresent(Double.self, forKey: .speed)
    }
}

// Source: rpc-schemas.ts `SpeechSettingsSchema`

/// The host's speech settings: the Dictation and Voice mode switches plus the three
/// provider sites. `llm`/`turnDetection` are read (the daemon accepts them) but never
/// edited by the Voice page, so only their provider/model ids are kept.
public struct SpeechSettings: Decodable, Sendable, Hashable {
    public var dictationEnabled: Bool
    public var dictationSTT: SpeechSite
    public var voiceModeEnabled: Bool
    public var voiceModeSTT: SpeechSite
    public var voiceModeTTS: SpeechSite
    public var llmProvider: String?
    public var llmModel: String?
    public var turnDetectionProvider: String?

    public init(
        dictationEnabled: Bool, dictationSTT: SpeechSite,
        voiceModeEnabled: Bool, voiceModeSTT: SpeechSite, voiceModeTTS: SpeechSite,
        llmProvider: String? = nil, llmModel: String? = nil, turnDetectionProvider: String? = nil
    ) {
        self.dictationEnabled = dictationEnabled
        self.dictationSTT = dictationSTT
        self.voiceModeEnabled = voiceModeEnabled
        self.voiceModeSTT = voiceModeSTT
        self.voiceModeTTS = voiceModeTTS
        self.llmProvider = llmProvider
        self.llmModel = llmModel
        self.turnDetectionProvider = turnDetectionProvider
    }

    public func site(_ id: SpeechSiteID) -> SpeechSite {
        switch id {
        case .dictationSTT: dictationSTT
        case .voiceModeSTT: voiceModeSTT
        case .voiceModeTTS: voiceModeTTS
        }
    }

    private enum K: String, CodingKey { case dictation, voiceMode, llm, turnDetection }
    private enum DictationK: String, CodingKey { case enabled, stt }
    private enum VoiceModeK: String, CodingKey { case enabled, stt, tts, llm, turnDetection }
    private enum ProviderModelK: String, CodingKey { case provider, model }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let dictation = try c.nestedContainer(keyedBy: DictationK.self, forKey: .dictation)
        dictationEnabled = try dictation.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        dictationSTT = (try? dictation.decode(SpeechSite.self, forKey: .stt))
            ?? SpeechSite(provider: .local)
        let voiceMode = try c.nestedContainer(keyedBy: VoiceModeK.self, forKey: .voiceMode)
        voiceModeEnabled = try voiceMode.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        voiceModeSTT = (try? voiceMode.decode(SpeechSite.self, forKey: .stt))
            ?? SpeechSite(provider: .local)
        voiceModeTTS = (try? voiceMode.decode(SpeechSite.self, forKey: .tts))
            ?? SpeechSite(provider: .local)
        let llm = try? voiceMode.nestedContainer(keyedBy: ProviderModelK.self, forKey: .llm)
        llmProvider = try llm?.decodeIfPresent(String.self, forKey: .provider)
        llmModel = try llm?.decodeIfPresent(String.self, forKey: .model)
        let turnDetection = try? voiceMode.nestedContainer(keyedBy: ProviderModelK.self, forKey: .turnDetection)
        turnDetectionProvider = try turnDetection?.decodeIfPresent(String.self, forKey: .provider)
    }
}

extension SpeechSettings {
    /// Decodes the `config.features` block (`DaemonConfig.features`, raw JSON). Nil when
    /// the daemon sent no speech block or a shape this client cannot read; a newer daemon
    /// adding fields still decodes, because unknown keys are ignored everywhere here.
    public init?(features: JSONValue?) {
        guard let features, features != .null,
            let data = try? JSONEncoder().encode(features),
            let decoded = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = decoded
    }
}

// MARK: - Site summary (what a settings row shows before it is opened)

/// `SpeechSiteSummary` upstream: what one Voice-page row says about a site.
public enum SpeechSiteSummary: Sendable, Hashable, Equatable {
    case local(modelLabel: String?)
    case openAI(model: String, missingKey: Bool)
    case unknown(provider: String)
}

/// `summarizeSpeechSite` upstream: the local model label, or the OpenAI model with
/// whether an API key (saved or env-provided) is missing.
public func summarizeSpeechSite(
    siteID: SpeechSiteID, site: SpeechSite, localModels: [LocalSpeechModel],
    envOverrides: [String: String]
) -> SpeechSiteSummary {
    switch site.provider {
    case .local:
        let resolved = resolveLocalModel(kind: siteID.kind, model: site.model, models: localModels)
        return .local(modelLabel: resolved?.label ?? site.model)
    case .openai:
        let hasEnvKey = envOverrides[siteID.fieldPath("apiKey")] != nil
        return .openAI(
            model: resolveOpenAIModel(kind: siteID.kind, model: site.model),
            missingKey: !site.hasApiKey && !hasEnvKey)
    case .unknown(let id):
        return .unknown(provider: id)
    }
}

// MARK: - Patch (deep-partial, null-clearing)

// Source: rpc-schemas.ts `SpeechSettingsPatchSchema` (fields accept `null` to clear them).

/// One field in a speech patch: absent (leave untouched), null (clear), or a value.
/// Modelled as a double optional so a patch can cancel a field without rewriting the rest.
public struct SpeechSitePatch: Sendable, Hashable {
    public var provider: SpeechProvider?
    public var model: String??
    public var apiKey: String??
    public var baseUrl: String??
    public var language: String??
    public var voice: String??
    public var confidenceThreshold: Double??
    public var speakerId: Int??
    public var speed: Double??

    public init(
        provider: SpeechProvider? = nil, model: String?? = nil, apiKey: String?? = nil,
        baseUrl: String?? = nil, language: String?? = nil, voice: String?? = nil,
        confidenceThreshold: Double?? = nil, speakerId: Int?? = nil, speed: Double?? = nil
    ) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.language = language
        self.voice = voice
        self.confidenceThreshold = confidenceThreshold
        self.speakerId = speakerId
        self.speed = speed
    }

    /// The wire object for one site patch. Only fields that were set appear; a cleared
    /// field is JSON `null`, which the daemon reads as "clear this field".
    public var jsonValue: JSONValue {
        var fields: [String: JSONValue] = [:]
        if let provider { fields["provider"] = .string(provider.wireValue) }
        if let model { fields["model"] = model.map(JSONValue.string) ?? .null }
        if let apiKey { fields["apiKey"] = apiKey.map(JSONValue.string) ?? .null }
        if let baseUrl { fields["baseUrl"] = baseUrl.map(JSONValue.string) ?? .null }
        if let language { fields["language"] = language.map(JSONValue.string) ?? .null }
        if let voice { fields["voice"] = voice.map(JSONValue.string) ?? .null }
        if let confidenceThreshold {
            fields["confidenceThreshold"] = confidenceThreshold.map { .number($0) } ?? .null
        }
        if let speakerId { fields["speakerId"] = speakerId.map { .number(Double($0)) } ?? .null }
        if let speed { fields["speed"] = speed.map { .number($0) } ?? .null }
        return .object(fields)
    }
}

/// The whole `features` patch for one save. Only the sites/switches being changed appear.
/// (`buildSpeechSitePatch` upstream wraps one site patch in the right section.)
public struct SpeechSettingsPatch: Sendable, Hashable {
    public var dictationEnabled: Bool?
    public var dictationSTT: SpeechSitePatch?
    public var voiceModeEnabled: Bool?
    public var voiceModeSTT: SpeechSitePatch?
    public var voiceModeTTS: SpeechSitePatch?

    public init(
        dictationEnabled: Bool? = nil, dictationSTT: SpeechSitePatch? = nil,
        voiceModeEnabled: Bool? = nil, voiceModeSTT: SpeechSitePatch? = nil,
        voiceModeTTS: SpeechSitePatch? = nil
    ) {
        self.dictationEnabled = dictationEnabled
        self.dictationSTT = dictationSTT
        self.voiceModeEnabled = voiceModeEnabled
        self.voiceModeSTT = voiceModeSTT
        self.voiceModeTTS = voiceModeTTS
    }

    public init(siteID: SpeechSiteID, patch: SpeechSitePatch) {
        switch siteID {
        case .dictationSTT: dictationSTT = patch
        case .voiceModeSTT: voiceModeSTT = patch
        case .voiceModeTTS: voiceModeTTS = patch
        }
    }

    /// The value for `DaemonConfigPatch.features`. Keys stay out when their section is
    /// untouched, so the daemon's deep-partial merge never sees an empty section.
    public var jsonValue: JSONValue {
        var fields: [String: JSONValue] = [:]
        if dictationEnabled != nil || dictationSTT != nil {
            var dictation: [String: JSONValue] = [:]
            if let dictationEnabled { dictation["enabled"] = .bool(dictationEnabled) }
            if let dictationSTT { dictation["stt"] = dictationSTT.jsonValue }
            fields["dictation"] = .object(dictation)
        }
        if voiceModeEnabled != nil || voiceModeSTT != nil || voiceModeTTS != nil {
            var voiceMode: [String: JSONValue] = [:]
            if let voiceModeEnabled { voiceMode["enabled"] = .bool(voiceModeEnabled) }
            if let voiceModeSTT { voiceMode["stt"] = voiceModeSTT.jsonValue }
            if let voiceModeTTS { voiceMode["tts"] = voiceModeTTS.jsonValue }
            fields["voiceMode"] = .object(voiceMode)
        }
        return .object(fields)
    }
}

// MARK: - Form fields and env overrides

// Source: speech-provider-form.ts `SpeechProviderField`, `buildFieldSources`

/// A field the provider sheet edits, keyed by its config field name.
public enum SpeechProviderField: String, Sendable, Hashable, CaseIterable {
    case provider, model, apiKey, baseUrl, language, voice
}

/// Where one field's effective value comes from. An env var set for a field other than the
/// fallback fields (`apiKey`, `baseUrl` — a saved value wins there) makes it read-only.
public struct SpeechFieldSource: Sendable, Hashable, Equatable {
    public var envVar: String?
    public var readOnly: Bool

    public init(envVar: String? = nil, readOnly: Bool = false) {
        self.envVar = envVar
        self.readOnly = readOnly
    }
}

/// `buildFieldSources` upstream: env vars the daemon reports for one site's fields.
public func speechFieldSources(
    siteID: SpeechSiteID, envOverrides: [String: String]
) -> [SpeechProviderField: SpeechFieldSource] {
    let fallbackFields: Set<SpeechProviderField> = [.apiKey, .baseUrl]
    return Dictionary(
        uniqueKeysWithValues: SpeechProviderField.allCases.map { field in
            let envVar = envOverrides[siteID.fieldPath(field.rawValue)]
            return (field, SpeechFieldSource(
                envVar: envVar,
                readOnly: envVar != nil && !fallbackFields.contains(field)))
        })
}

// MARK: - Option lists and defaults (voice-settings.ts)

// OpenAI accepts free-form ids so self-hosted servers can use their own; the sheet
// offers these and keeps a saved id outside the list visible as an option.
public func openAIModelIDs(kind: SpeechModelKind) -> [String] {
    switch kind {
    case .stt: ["whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"]
    case .tts: ["tts-1", "tts-1-hd", "gpt-4o-mini-tts"]
    }
}

public func openAIDefaultModelID(kind: SpeechModelKind) -> String {
    kind == .stt ? "whisper-1" : "tts-1"
}

public func resolveOpenAIModel(kind: SpeechModelKind, model: String?) -> String {
    model ?? openAIDefaultModelID(kind: kind)
}

public let openAIVoiceIDs = ["alloy", "ash", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]
public let openAIDefaultVoice = "alloy"

public func resolveOpenAIVoice(_ voice: String?) -> String {
    voice ?? openAIDefaultVoice
}

public struct SpeechModelOption: Sendable, Hashable, Equatable {
    public var value: String
    public var label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

private func withSelected(
    _ options: [SpeechModelOption], selected: String
) -> [SpeechModelOption] {
    guard !selected.isEmpty, !options.contains(where: { $0.value == selected }) else { return options }
    return options + [SpeechModelOption(value: selected, label: selected)]
}

public func openAIModelOptions(kind: SpeechModelKind, selected: String) -> [SpeechModelOption] {
    withSelected(openAIModelIDs(kind: kind).map { SpeechModelOption(value: $0, label: $0) }, selected: selected)
}

public func openAIVoiceOptions(selected: String) -> [SpeechModelOption] {
    withSelected(openAIVoiceIDs.map { SpeechModelOption(value: $0, label: $0) }, selected: selected)
}

/// `resolveLocalModel` upstream: the saved model, else the kind's default.
public func resolveLocalModel(
    kind: SpeechModelKind, model: String?, models: [LocalSpeechModel]
) -> LocalSpeechModel? {
    let kindModels = models.filter { $0.kind == kind.rawValue }
    if let model { return kindModels.first { $0.id == model } }
    return kindModels.first { $0.isDefault }
}

// MARK: - Local speech models

// Source: rpc-schemas.ts `LocalSpeechModelSchema`

/// What the daemon is doing with one local model file. Unknown values are kept raw.
public enum LocalSpeechModelStatus: Sendable, Hashable, Equatable {
    case installed
    case notInstalled
    case downloading
    case extracting
    case failed
    case unknown(String)

    public init(wire: String) {
        switch wire {
        case "installed": self = .installed
        case "not_installed": self = .notInstalled
        case "downloading": self = .downloading
        case "extracting": self = .extracting
        case "failed": self = .failed
        default: self = .unknown(wire)
        }
    }
}

public struct LocalSpeechModel: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    /// `"stt"` or `"tts"` (a string on the wire; unknown kinds stay comparable).
    public var kind: String
    public var label: String
    public var description: String
    public var languages: [String]
    public var downloadSizeBytes: Double
    public var isDefault: Bool
    /// Selected by an enabled feature; the daemon keeps it installed.
    public var inUse: Bool
    public var status: LocalSpeechModelStatus
    public var receivedBytes: Double?
    public var totalBytes: Double?
    public var error: String?

    public init(
        id: String, kind: String, label: String, description: String, languages: [String],
        downloadSizeBytes: Double, isDefault: Bool, inUse: Bool, status: LocalSpeechModelStatus,
        receivedBytes: Double? = nil, totalBytes: Double? = nil, error: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.description = description
        self.languages = languages
        self.downloadSizeBytes = downloadSizeBytes
        self.isDefault = isDefault
        self.inUse = inUse
        self.status = status
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.error = error
    }

    private enum K: String, CodingKey {
        case id, kind, label, description, languages, downloadSizeBytes, isDefault, inUse
        case status, receivedBytes, totalBytes, error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? id
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? []
        downloadSizeBytes = try c.decodeIfPresent(Double.self, forKey: .downloadSizeBytes) ?? 0
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        inUse = try c.decodeIfPresent(Bool.self, forKey: .inUse) ?? false
        status = LocalSpeechModelStatus(wire: try c.decodeIfPresent(String.self, forKey: .status) ?? "")
        receivedBytes = try c.decodeIfPresent(Double.self, forKey: .receivedBytes)
        totalBytes = try c.decodeIfPresent(Double.self, forKey: .totalBytes)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

// Source: rpc-schemas.ts `SpeechLocalModelsListRequestSchema` / `…ResponseSchema`
// (permissions: list `daemon.read`, download/delete `daemon.manage`).

public struct SpeechLocalModelsListRequest: PaseoRequest {
    public static let type = "speech.local_models.list.request"
    public static let responseType = "speech.local_models.list.response"
    public var requestId = ""
    public init() {}

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var models: [LocalSpeechModel]
        public var error: String?

        private enum K: String, CodingKey { case requestId, models, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            models = (try? c.decodeIfPresent([LocalSpeechModel].self, forKey: .models)) ?? []
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}

// Source: rpc-schemas.ts `SpeechLocalModelsDownloadRequestSchema` / `…ResponseSchema`
// (resolves once the download *starts*; the list is polled for progress).

public struct SpeechLocalModelsDownloadRequest: PaseoRequest {
    public static let type = "speech.local_models.download.request"
    public static let responseType = "speech.local_models.download.response"
    public var requestId = ""
    public var modelId: String
    public init(modelId: String) { self.modelId = modelId }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var error: String?

        private enum K: String, CodingKey { case requestId, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}

// Source: rpc-schemas.ts `SpeechLocalModelsDeleteRequestSchema` / `…ResponseSchema`

public struct SpeechLocalModelsDeleteRequest: PaseoRequest {
    public static let type = "speech.local_models.delete.request"
    public static let responseType = "speech.local_models.delete.response"
    public var requestId = ""
    public var modelId: String
    public init(modelId: String) { self.modelId = modelId }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var error: String?

        private enum K: String, CodingKey { case requestId, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}

// MARK: - Model state, sizes, languages (voice-settings.ts)

/// `LocalModelState` upstream: what a catalog row shows for one model.
public enum LocalModelState: Sendable, Hashable, Equatable {
    case installed
    case notInstalled
    case downloading(percent: Int?)
    case extracting
    case failed(error: String)
}

public func localModelState(of model: LocalSpeechModel) -> LocalModelState {
    switch model.status {
    case .installed:
        return .installed
    case .downloading:
        let total = model.totalBytes ?? 0
        let received = model.receivedBytes ?? 0
        return .downloading(percent: total > 0 ? min(100, Int((received / total) * 100)) : nil)
    case .extracting:
        return .extracting
    case .failed:
        return .failed(error: model.error ?? "")
    case .notInstalled:
        return .notInstalled
    case .unknown:
        return .notInstalled
    }
}

/// `isLocalModelBusy` upstream: the daemon reports download progress through the list,
/// so the client polls the list while any model is downloading or extracting.
public func isLocalModelBusy(_ model: LocalSpeechModel) -> Bool {
    model.status == .downloading || model.status == .extracting
}

/// `formatModelSize` upstream (decimal megabytes; 1 GB and up shows one decimal).
public func formatModelSize(bytes: Double) -> String {
    let megabytes = bytes / 1_000_000
    if megabytes >= 1000 { return "\(String(format: "%.1f", megabytes / 1000)) GB" }
    return "\(Int(megabytes.rounded())) MB"
}

/// Multilingual models list close to a hundred languages; past this many the label names
/// the first ones and counts the rest (`formatLanguages` upstream uses
/// `Intl.DisplayNames`; here each code maps through the current locale, falling back to
/// the uppercased code when no name is known).
public func formatLanguages(
    languages: [String], formatMore: (String, Int) -> String
) -> String {
    let listed = languages.prefix(10).map { code in
        Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }.joined(separator: ", ")
    let hidden = languages.count - 10
    return hidden > 0 ? formatMore(listed, hidden) : listed
}
