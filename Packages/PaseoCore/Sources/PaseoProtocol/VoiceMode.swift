import Foundation

// Realtime voice mode: the wire types for entering the voice lane, streaming mic audio,
// receiving synthesized replies and acknowledging playback.
//
// Source: packages/protocol/src/messages.ts `VoiceAudioChunkMessageSchema`,
// `AudioPlayedMessageSchema`, `SetVoiceModeMessageSchema`,
// `SetVoiceModeResponseMessageSchema`, `AssistantChunkMessageSchema`,
// `AudioOutputMessageSchema`, `TranscriptionResultMessageSchema`,
// `VoiceInputStateMessageSchema`, `ServerCapabilityStateSchema`,
// `ServerVoiceCapabilitiesSchema`, `ServerCapabilitiesSchema`; client capability
// `capabilities.voice` (`messages.ts:7990`). The response/state machine mirrors the
// upstream app's `app/voice/voice-runtime.ts`; the store lives in
// `VoiceModeSession.swift`. The pushes (`audio_output`, `voice_input_state`,
// `transcription_result`) arrive through the daemon's per-socket voice `OwnedOperation`
// (`packages/server/src/server/session/voice/index.ts`), created when `set_voice_mode`
// starts the session — no client subscription is involved.

// MARK: - Capability switch

/// Realtime voice: the one switch for the `voice` hello capability, mirroring
/// `OwnedSubscriptions.isEnabled`. The client advertises `capabilities.voice` only while
/// true; flip to false and rebuild if a daemon misbehaves with voice mode.
public enum VoiceMode {
    /// `capabilities.voice` in the hello. Source: `messages.ts:7992`
    /// (`capabilities: { voice: z.boolean().optional(), … }`).
    public static let capability = "voice"
    public static let isEnabled = true
}

// MARK: - Daemon readiness (`server_info.capabilities.voice`)

// Source: messages.ts `ServerCapabilityStateSchema`, `ServerVoiceCapabilitiesSchema`,
// `ServerCapabilitiesSchema`

/// One capability's daemon readiness: enabled plus the reason text the app shows when it
/// is not ready (`server-info-capabilities.ts` `resolveVoiceUnavailableMessage`).
public struct ServerCapabilityState: Decodable, Sendable, Hashable {
    public var enabled: Bool
    public var reason: String

    public init(enabled: Bool, reason: String = "") {
        self.enabled = enabled
        self.reason = reason
    }

    private enum K: String, CodingKey { case enabled, reason }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }

    /// Whether this capability can be used: enabled with an empty reason
    /// (`resolveVoiceUnavailableMessage` returns nil exactly then).
    public var isUsable: Bool { enabled && reason.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The message to show the user when unusable ("" when usable).
    public var unavailableMessage: String {
        reason.trimmingCharacters(in: .whitespaces)
    }
}

public struct ServerVoiceCapabilities: Decodable, Sendable, Hashable {
    public var dictation: ServerCapabilityState
    public var voice: ServerCapabilityState

    public init(dictation: ServerCapabilityState, voice: ServerCapabilityState) {
        self.dictation = dictation
        self.voice = voice
    }

    private enum K: String, CodingKey { case dictation, voice }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        dictation = (try? c.decode(ServerCapabilityState.self, forKey: .dictation))
            ?? ServerCapabilityState(enabled: false)
        voice = (try? c.decode(ServerCapabilityState.self, forKey: .voice))
            ?? ServerCapabilityState(enabled: false)
    }
}

public struct ServerCapabilities: Decodable, Sendable, Hashable {
    public var voice: ServerVoiceCapabilities?

    public init(voice: ServerVoiceCapabilities? = nil) {
        self.voice = voice
    }

    private enum K: String, CodingKey { case voice }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        voice = try? c.decode(ServerVoiceCapabilities.self, forKey: .voice)
    }
}

// MARK: - set_voice_mode

// Source: messages.ts `SetVoiceModeMessageSchema`, `SetVoiceModeResponseMessageSchema`

/// Enters or leaves the voice lane for the session's active agent (or `agentId`).
/// `requestId` is optional on the wire; the client passes one so the response correlates.
public struct SetVoiceModeRequest: PaseoRequest {
    public static let type = "set_voice_mode"
    public static let responseType = "set_voice_mode_response"
    public var requestId = ""
    public var enabled: Bool
    public var agentId: String?

    public init(enabled: Bool, agentId: String? = nil) {
        self.enabled = enabled
        self.agentId = agentId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var enabled: Bool
        /// Required, nullable: the agent the daemon bound the lane to (nil = none).
        public var agentId: String?
        public var accepted: Bool
        public var error: String?
        public var reasonCode: String?
        public var retryable: Bool?
        public var missingModelIds: [String]?

        private enum K: String, CodingKey {
            case requestId, enabled, agentId, accepted, error, reasonCode, retryable, missingModelIds
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            agentId = try c.decodeIfPresent(String.self, forKey: .agentId) ?? nil
            accepted = try c.decodeIfPresent(Bool.self, forKey: .accepted) ?? false
            error = try c.decodeIfPresent(String.self, forKey: .error)
            reasonCode = try c.decodeIfPresent(String.self, forKey: .reasonCode)
            retryable = try c.decodeIfPresent(Bool.self, forKey: .retryable)
            missingModelIds = try c.decodeIfPresent([String].self, forKey: .missingModelIds)
        }
    }
}

// MARK: - Mic chunks and playback acks (fire-and-forget)

// Source: messages.ts `VoiceAudioChunkMessageSchema`, `AudioPlayedMessageSchema`

/// One chunk of mic PCM sent to the daemon. Format is `audio/pcm;rate=16000;bits=16`
/// (`voice-runtime.ts` `PCM_MIME_TYPE`); `isLast` is false for the continuous stream.
public struct VoiceAudioChunk: PaseoOutboundMessage {
    public static let type = "voice_audio_chunk"
    public var audio: String
    public var format: String
    public var isLast: Bool

    public init(audio: String, format: String = VoiceWire.pcmMimeType, isLast: Bool = false) {
        self.audio = audio
        self.format = format
        self.isLast = isLast
    }
}

/// Tells the daemon a playback chunk was played (or dropped) so it can free buffers.
public struct AudioPlayed: PaseoOutboundMessage {
    public static let type = "audio_played"
    public var id: String
    public init(id: String) { self.id = id }
}

// MARK: - Voice lane pushes

// Source: messages.ts `AudioOutputMessageSchema`, `TranscriptionResultMessageSchema`,
// `VoiceInputStateMessageSchema`

/// One TTS chunk from the daemon. `isVoiceMode` is drift protection: drop audio tagged
/// for a lane the client is not in (`voice-runtime.ts` `handleAudioOutput`).
public struct AudioOutputPayload: Decodable, Sendable, Hashable {
    public var audio: String
    public var format: String
    public var id: String
    public var isVoiceMode: Bool
    public var groupId: String?
    public var chunkIndex: Int?
    public var isLastChunk: Bool?

    public init(
        audio: String, format: String, id: String, isVoiceMode: Bool,
        groupId: String? = nil, chunkIndex: Int? = nil, isLastChunk: Bool? = nil
    ) {
        self.audio = audio
        self.format = format
        self.id = id
        self.isVoiceMode = isVoiceMode
        self.groupId = groupId
        self.chunkIndex = chunkIndex
        self.isLastChunk = isLastChunk
    }

    private enum K: String, CodingKey {
        case audio, format, id, isVoiceMode, groupId, chunkIndex, isLastChunk
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        audio = try c.decodeIfPresent(String.self, forKey: .audio) ?? ""
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        isVoiceMode = try c.decodeIfPresent(Bool.self, forKey: .isVoiceMode) ?? false
        groupId = try c.decodeIfPresent(String.self, forKey: .groupId)
        chunkIndex = try c.decodeIfPresent(Int.self, forKey: .chunkIndex)
        isLastChunk = try c.decodeIfPresent(Bool.self, forKey: .isLastChunk)
    }
}

/// The daemon's STT verdict for a speech segment. Upstream only flips the phase
/// (non-empty → `waiting`, empty → `listening`, `voice-runtime.ts`), the transcript
/// itself enters the timeline as the user's message; the runtime does not insert drafts.
public struct TranscriptionResultPayload: Decodable, Sendable, Hashable {
    public var text: String
    public var language: String?
    public var duration: Double?
    public var requestId: String
    public var avgLogprob: Double?
    public var isLowConfidence: Bool?
    public var byteLength: Double?
    public var format: String?

    public init(
        text: String, language: String? = nil, duration: Double? = nil,
        requestId: String = "", avgLogprob: Double? = nil, isLowConfidence: Bool? = nil,
        byteLength: Double? = nil, format: String? = nil
    ) {
        self.text = text
        self.language = language
        self.duration = duration
        self.requestId = requestId
        self.avgLogprob = avgLogprob
        self.isLowConfidence = isLowConfidence
        self.byteLength = byteLength
        self.format = format
    }

    private enum K: String, CodingKey {
        case text, language, duration, requestId, avgLogprob, isLowConfidence, byteLength, format
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        language = try c.decodeIfPresent(String.self, forKey: .language)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
        avgLogprob = try c.decodeIfPresent(Double.self, forKey: .avgLogprob)
        isLowConfidence = try c.decodeIfPresent(Bool.self, forKey: .isLowConfidence)
        byteLength = try c.decodeIfPresent(Double.self, forKey: .byteLength)
        format = try c.decodeIfPresent(String.self, forKey: .format)
    }
}

/// Turn-detection VAD: the user is speaking (used for the meter and for interrupting
/// playback). `voice-runtime.ts` `onServerSpeechStateChanged`.
public struct VoiceInputStatePayload: Decodable, Sendable, Hashable {
    public var isSpeaking: Bool
    public init(isSpeaking: Bool) { self.isSpeaking = isSpeaking }

    private enum K: String, CodingKey { case isSpeaking }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        isSpeaking = try c.decodeIfPresent(Bool.self, forKey: .isSpeaking) ?? false
    }
}

// MARK: - Wire constants

/// `PCM_MIME_TYPE` and the playback MIME mapping from `voice-runtime.ts`.
public enum VoiceWire {
    /// Mic upload format: 16-bit mono PCM at 16 kHz.
    public static let pcmMimeType = "audio/pcm;rate=16000;bits=16"

    /// Data mime type for one playback chunk (`toPlaybackSource` upstream):
    /// daemon PCM is 24 kHz; mp3 passes through; anything else becomes `audio/<format>`.
    public static func playbackMimeType(format: String) -> String {
        switch format {
        case "pcm": "audio/pcm;rate=24000;bits=16"
        case "mp3": "audio/mpeg"
        default: "audio/\(format)"
        }
    }

    /// Decodes base64 audio output; empty for malformed input (never throws).
    public static func decodeAudio(_ base64: String) -> Data {
        Data(base64Encoded: base64) ?? Data()
    }

    /// Base64 of raw PCM bytes.
    public static func encodePCM(_ data: Data) -> String {
        data.base64EncodedString()
    }
}
