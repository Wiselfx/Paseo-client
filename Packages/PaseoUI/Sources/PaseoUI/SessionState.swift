import Foundation

public struct ChatMessage: Identifiable, Equatable, Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public var id: UUID
    public var role: Role
    public var text: String
    public var media: [ClaudeMedia]
    public init(id: UUID = UUID(), role: Role, text: String, media: [ClaudeMedia] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.media = media
    }
}

public enum ClaudeAppearance: String, CaseIterable, Sendable { case system = "System", light = "Light", dark = "Dark" }
public enum ClaudeVoice: String, CaseIterable, Sendable { case clara = "Clara", suave = "Suave" }
public enum ComposerPhase: Equatable, Sendable { case idle, streaming, recording, recordingPaused }
public enum Effort: String, CaseIterable, Sendable {
    case low = "Low", medium = "Medium", high = "High", extra = "Extra", max = "Max"
}
public enum ClaudeModel: String, CaseIterable, Sendable {
    case fable = "Fable 5.1", opus = "Opus 5.5", sonnet = "Sonnet 5.5", haiku = "Haiku 5.5"
    public var detail: String {
        switch self {
        case .fable: "For your toughest challenges"
        case .opus: "For complex work and everyday tasks"
        case .sonnet: "Most efficient for simpler tasks"
        case .haiku: "Fastest for quick answers"
        }
    }
}
/// Intents are delivered to the integrating app; the UI has no networking or device access.
@nonexhaustive public enum ClaudeAction: Equatable, Sendable {
    case send(String), stop, startDictation, stopDictation, cancelDictation, commitDictation
    case newSession, selectModel(ClaudeModel), selectEffort(Effort), setAutomaticApproval(Bool)
    case setDeviceEnabled(Bool), startVoice, attach(String), removeAttachment(String)
    case openCode, code(CodeAction)
    case openProjects, projects(ProjectAction)
    case settings(ClaudeSettingsAction)
    case media(ClaudeMediaAction)
    case markdown(UUID, MarkdownAction)
    case endVoice, toggleVoiceInput, toggleVoiceOutput, selectVoice(ClaudeVoice), selectVoiceLanguage(String)
    case copy(UUID)
}

public struct SessionState: Equatable, Sendable {
    public var settings = ClaudeSettingsState()
    public var appearance: ClaudeAppearance = .dark
    public var draft = ""
    public var messages: [ChatMessage] = []
    public var phase: ComposerPhase = .idle
    public private(set) var responseID: UUID?
    public var model: ClaudeModel = .opus
    public var effort: Effort = .high
    public var automaticApproval = false
    public var deviceEnabled = true
    public var code = CodeState()
    public var projects = ProjectState()
    public private(set) var showingProjects = false
    public private(set) var showingCode = false
    public private(set) var voiceActive = false
    public private(set) var voiceInputEnabled = true
    public private(set) var voiceOutputMuted = false
    public var voice: ClaudeVoice = .suave
    public var voiceLanguage = "Spanish (Latin America)"
    public var attachments: [String] = []
    public var media = ClaudeMediaState()
    public var transcript = ""
    /// Host-supplied UI levels only. Nonfinite values become silence, values clamp
    /// to 0...1, and only the newest256 samples are retained. No audio is captured.
    public var dictationLevels: [Double] = [] {
        didSet { dictationLevels = DictationWaveformMetrics.normalized(dictationLevels) }
    }
    public private(set) var draftBeforeDictation = ""
    public init() {}
    public var canSend: Bool {
        phase == .idle
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
                || !media.draft.isEmpty)
    }
    public mutating func reduce(_ action: ClaudeAction) {
        switch action {
        case .send(let text):
            guard phase == .idle,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
                    || !media.draft.isEmpty
            else { return }
            let attachmentText =
                attachments.isEmpty ? "" : attachments.joined(separator: ", ") + (text.isEmpty ? "" : "\n")
            messages.append(.init(role: .user, text: attachmentText + text, media: media.draft))
            draft = ""
            attachments = []
            media.draft = []
            media.reduce(.close)
            phase = .streaming
            responseID = UUID()
        case .stop:
            if phase == .streaming {
                phase = .idle
                responseID = nil
            }
        case .startDictation:
            guard phase == .idle, !voiceActive else { return }
            draftBeforeDictation = draft
            transcript = ""
            dictationLevels = []
            phase = .recording
        case .stopDictation:
            guard phase == .recording else { return }
            dictationLevels = []
            if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft = draftBeforeDictation
                transcript = ""
                dictationLevels = []
                phase = .idle
            } else {
                phase = .recordingPaused
            }  // Content-bearing stop remains an unverified host-preview state.
        case .cancelDictation:
            guard phase == .recording || phase == .recordingPaused else { return }
            draft = draftBeforeDictation
            transcript = ""
            dictationLevels = []
            phase = .idle
        case .commitDictation:
            guard phase == .recording || phase == .recordingPaused else { return }
            draft = [draftBeforeDictation, transcript].filter { !$0.isEmpty }.joined(separator: " ")
            transcript = ""
            dictationLevels = []
            phase = .idle
        case .newSession:
            let model = model, effort = effort, automatic = automaticApproval, device = deviceEnabled,
                appearance = appearance, voice = voice, language = voiceLanguage, code = code, projects = projects,
                recentMedia = media.recent, settings = settings
            self = SessionState()
            self.settings = settings
            self.settings.reduce(.close)
            self.media.recent = recentMedia
            self.projects = projects
            self.projects.reduce(.cancel)
            self.code = code
            self.code.reduce(.closeRoutines)
            self.code.reduce(.closeNewSession)
            self.appearance = appearance
            self.voice = voice
            self.voiceLanguage = language
            self.model = model
            self.effort = effort
            automaticApproval = automatic
            deviceEnabled = device
        case .settings(let action):
            settings.reduce(action)
            if case .setAppearance(let value) = action { appearance = value }
        case .media(let action): media.reduce(action)
        case .openProjects:
            showingProjects = true
            showingCode = false
        case .projects(let action): projects.reduce(action)
        case .openCode:
            showingProjects = false
            showingCode = true
        case .code(let action): code.reduce(action)
        case .selectModel(let value): model = value
        case .selectEffort(let value): effort = value
        case .setAutomaticApproval(let value): automaticApproval = value
        case .setDeviceEnabled(let value): deviceEnabled = value
        case .attach(let name): if !attachments.contains(name) { attachments.append(name) }
        case .removeAttachment(let name): attachments.removeAll { $0 == name }
        case .startVoice: if phase == .idle { voiceActive = true }
        case .endVoice:
            voiceActive = false
            voiceInputEnabled = true
            voiceOutputMuted = false
        case .toggleVoiceInput: if voiceActive { voiceInputEnabled.toggle() }
        case .toggleVoiceOutput: if voiceActive { voiceOutputMuted.toggle() }
        case .selectVoice(let value): voice = value
        case .selectVoiceLanguage(let value): voiceLanguage = value
        case .copy, .markdown: break
        }
    }
    /// Backends and demos both deliver response text here. Late chunks after Stop are ignored.
    public mutating func appendResponse(_ text: String, responseID: UUID) {
        guard phase == .streaming, self.responseID == responseID else { return }
        if messages.last?.role == .assistant {
            messages[messages.count - 1].text += text
        } else {
            messages.append(.init(role: .assistant, text: text))
        }
    }
    public mutating func finishResponse(responseID: UUID) {
        if phase == .streaming, self.responseID == responseID {
            phase = .idle
            self.responseID = nil
        }
    }
}
