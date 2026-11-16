import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Realtime voice mode for this socket: enter/leave the voice lane, stream mic PCM, queue
/// synthesized replies for the UI's audio engine and ack them.
///
/// A port of the upstream app's `app/voice/voice-runtime.ts` state machine:
/// phases, playback groups with ordered chunks and `audio_played` acks, the volume
/// smoothing, and the `voice_input_state` interrupt that resets playback. The pushes
/// (`audio_output`, `voice_input_state`, `transcription_result`) arrive through the
/// daemon's per-socket voice operation (`session/voice/index.ts`), so the client starts
/// no subscription: once `set_voice_mode` lands the operation owns the lane for this
/// socket, and a dropped socket drops it (the store just resets, then re-issues
/// `set_voice_mode` on reconnect, exactly like `resyncVoiceMode` upstream).
///
/// The UI owns recording/rendering and calls in: `handleCapturePCM` for every mic chunk,
/// `handleCaptureVolume` for the mic level, `didPlayChunk` when the engine finished a
/// `nextAudioChunk`. `playbackStopRequested` is the signal to stop the engine *now*
/// (interrupt, stop, agent switch, disconnect).
///
/// IMPLEMENTATION TICKET: docs/tickets/M15-voice-mode.md
@MainActor @Observable
public final class VoiceModeSession {
    /// `VoiceRuntimePhase` upstream (minus `submitting`, which is only the engine hook
    /// here: submission is the fire-and-forget `voice_audio_chunk` send).
    public enum Phase: Sendable, Equatable {
        case disabled
        case starting
        case listening
        case waiting
        case playing
        case stopping
    }

    /// One decoded playback chunk the audio engine should play next
    /// (`StreamingPlaybackChunk` upstream): id for the ack, ordered position and data.
    public struct AudioPlaybackChunk: Sendable, Equatable {
        public var id: String
        public var groupId: String
        public var chunkIndex: Int
        public var data: Data
        public var format: String

        public init(id: String, groupId: String, chunkIndex: Int, data: Data, format: String) {
            self.id = id
            self.groupId = groupId
            self.chunkIndex = chunkIndex
            self.data = data
            self.format = format
        }
    }

    /// Whether voice mode is active for the open agent (`isVoiceMode` upstream).
    /// True only once the lane is up — during `.starting` the server hasn't accepted yet.
    public var isVoiceMode: Bool {
        activeAgentId != nil && phase != .disabled && phase != .starting
    }
    /// Whether voice mode is active for one agent.
    public func isVoiceMode(for agentId: String) -> Bool {
        isVoiceMode && activeAgentId == agentId
    }

    /// Whether the UI may play the thinking tone (`canPlayCue` upstream): the lane is
    /// waiting for a reply and the daemon hasn't heard the user speak. Timing (the
    /// 1.5 s delay before the first tone, the repeat gap) lives with the engine; the
    /// store only publishes when the tone is allowed at all.
    public var isThinkingToneExpected: Bool {
        isVoiceMode && phase == .waiting && !isSpeaking
    }

    public private(set) var phase: Phase = .disabled
    public private(set) var activeAgentId: String?
    public private(set) var isVoiceSwitching = false
    public private(set) var isMuted = false
    /// Last start/stop failure (daemon text, with the reason code appended like
    /// `packages/client/src/daemon-client.ts` `setVoiceMode`). Cleared by the next success.
    public private(set) var error: String?
    /// Models the daemon asked for before voice mode can run. Point the user at
    /// Settings → Voice to download them; the UI reads this for the hint.
    public private(set) var missingModelIds: [String] = []
    /// Last assistant-audio failure (playback faults aren't fatal; matches them going to
    /// the console upstream). Nil after a clean play cycle.
    public private(set) var lastPlaybackError: String?

    // Telemetry (upstream `VoiceRuntimeTelemetrySnapshot`).
    /// Smoothed mic level 0…1, published at most every 120 ms or on a 0.02 change.
    public private(set) var volume: Double = 0
    /// Server-side VAD (`voice_input_state`): the daemon hears the user speaking.
    public private(set) var isSpeaking = false

    /// Whether the daemon says realtime voice is usable (gate for the composer button).
    public private(set) var isVoiceAvailable = false
    /// The daemon's reason when voice is unusable ("" when usable).
    public private(set) var unavailableReason = ""

    /// The chunk the engine should play now; nil when the queue is empty.
    /// The engine plays it, then calls `didPlayChunk(id:)` (or `didFailChunk(id:)`).
    public private(set) var nextAudioChunk: AudioPlaybackChunk?
    /// Bumped whenever the engine must stop playback immediately (interrupt, stop,
    /// agent switch, disconnect, resync).
    public private(set) var playbackStopRequested: UInt64 = 0
    /// Whether an utterance is currently playing (`setAssistantAudioPlaying` upstream).
    public private(set) var isAssistantAudioPlaying = false

    private let client: any DaemonClient
    private var readiness: ServerCapabilityState?
    /// PIPE: `transportReady` upstream — PCM is streamed only once set, and a reconnect
    /// clears it until the resync lands.
    private var transportReady = false
    private var connectionGeneration: UInt64 = 0
    private var turnInProgress = false
    private var generation = 0
    private var lastVolumePublish = 0.0  // ms, same epoch as `nowMs` parameters

    private struct PlaybackGroup {
        var id: String
        var isVoiceMode: Bool
        var shouldPlay: Bool
        /// Playback session generation when the group was created (`generation` in the
        /// upstream runtime). Bumped by `resetPlaybackState`; stale groups never advance.
        var generation: UInt64
        var chunks: [Int: AudioPlaybackChunk] = [:]
        var nextChunkToPlay = 0
        var finalChunkIndex: Int?
        var started = false
    }

    private var groups: [String: PlaybackGroup] = [:]
    private var groupOrder: [String] = []
    private var activeGroupId: String?
    /// One per playback reset, like upstream's `playback.generation`: acks that arrive
    /// after a stop/interrupt must be ignored as stale.
    private var playbackGeneration: UInt64 = 0

    public init(client: any DaemonClient) {
        self.client = client
    }

    // MARK: Enter / leave

    /// Enters voice mode for one agent (`startVoice` upstream, minus engine/keep-awake,
    /// which the UI layers own). Returns false with `error` set when the daemon refuses
    /// or the host can't do voice. The caller must not start while a turn is already
    /// running upstream blocks that with "Interrupt the agent before starting voice mode".
    @discardableResult
    public func start(agentId: String) async -> Bool {
        guard let readiness, readiness.isUsable else {
            error = readiness?.unavailableMessage.isEmpty == false
                ? readiness?.unavailableMessage
                : "Voice mode is not available on this host."
            return false
        }
        if activeAgentId == agentId, isVoiceMode { return true }

        let generation = self.generation + 1
        self.generation = generation
        let wasVoice = isVoiceMode
        transportReady = false
        isVoiceSwitching = true
        phase = .starting

        do {
            // Switching agents ends the previous lane first (no agentId: the daemon
            // clears the session's active agent, like upstream's stop path).
            if wasVoice, activeAgentId != agentId {
                _ = try? await client.send(SetVoiceModeRequest(enabled: false))
            }
            let response = try await client.send(
                SetVoiceModeRequest(enabled: true, agentId: agentId))
            if !response.accepted {
                guard generation == self.generation else { return false }
                error = voiceErrorText(response)
                missingModelIds = response.missingModelIds ?? []
                transportReady = false
                phase = .disabled
                isVoiceSwitching = false
                return false
            }
            guard generation == self.generation else { return false }
            transportReady = true
            turnInProgress = false
            error = nil
            missingModelIds = []
            activeAgentId = agentId
            phase = .listening
            return true
        } catch let failure {
            guard generation == self.generation else { return false }
            error = String(describing: failure)
            transportReady = false
            phase = .disabled
            isVoiceSwitching = false
            return false
        }
    }

    /// Leaves voice mode: cancels the running turn (upstream's `stopRealtimeVoice`
    /// cancels the agent before stopping the lane), clears playback, then tells the
    /// daemon. Works mid-`.starting` too: hung start responses are dropped by the
    /// generation bump and the lane is torn down (`stopVoice` upstream).
    /// The store always lands back at `.disabled`, even when a send fails.
    @discardableResult
    public func stop() async -> Bool {
        let wasStarting = phase == .starting
        guard wasStarting || isVoiceMode else { return true }
        let agentId = activeAgentId
        let generation = self.generation + 1
        self.generation = generation
        phase = .stopping
        isVoiceSwitching = true
        playbackStopRequested &+= 1
        resetPlaybackState()

        var failed = false
        do {
            if turnInProgress, let agentId {
                _ = try await client.send(CancelAgentRequest(agentId: agentId))
            }
            _ = try await client.send(SetVoiceModeRequest(enabled: false))
        } catch let failure {
            failed = true
            error = String(describing: failure)
        }
        guard generation == self.generation else { return false }
        transportReady = false
        turnInProgress = false
        clearCaptureTelemetry()
        activeAgentId = nil
        phase = .disabled
        isVoiceSwitching = false
        isMuted = false
        return !failed
    }

    /// Mute/unmute the mic. While muted, chunks are dropped (upstream `toggleMute`
    /// resets the uploader and the volume telemetry).
    public func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        if muted {
            clearCaptureTelemetry()
        }
    }

    // MARK: Mic in (UI -> store -> daemon)

    /// Forwards one mic PCM chunk (exact 16 kHz int16 bytes) to the daemon, unless out
    /// of voice mode, muted, or the transport broke. Send failures drop the chunk
    /// (upstream logs and keeps going).
    public func handleCapturePCM(_ data: Data) {
        guard transportReady, isVoiceMode, !isMuted, !data.isEmpty else { return }
        let chunk = VoiceAudioChunk(audio: VoiceWire.encodePCM(data))
        let client = self.client
        Task {
            try? await client.send(chunk)
        }
    }

    /// The mic level, same smoothing as upstream (`publishDisplayVolume`):
    /// attack 0.35, release 0.18, publish every 120 ms or on a 0.02 change.
    /// `now` is injectable for tests; the UI passes `Date()`.
    public func handleCaptureVolume(_ level: Double, now: Date = Date()) {
        let displayLevel = isMuted ? 0 : level
        let nowMs = now.timeIntervalSince1970 * 1000
        let previous = volume
        let smoothing: Double = displayLevel >= previous ? 0.35 : 0.18
        var next = previous + (displayLevel - previous) * smoothing
        next = max(0, min(1, next))
        let enoughTime = nowMs - lastVolumePublish >= 120
        let enoughChange = abs(next - previous) >= 0.02
        guard enoughTime || enoughChange else { return }
        lastVolumePublish = nowMs
        volume = (next * 1000).rounded() / 1000
    }

    // MARK: Daemon pushes (HostSession routing)

    /// `audio_output` frames. Drift protection first: only voice-lane audio is queued
    /// (`isVoiceMode` on the payload, `handleAudioOutput` upstream). Malformed base64
    /// decodes to empty data and still acks (the engine plays nothing, then acks).
    public func handleAudioOutput(_ payload: AudioOutputPayload) {
        guard isVoiceMode, payload.isVoiceMode else { return }
        let groupId = payload.groupId ?? payload.id
        let chunkIndex = payload.chunkIndex ?? 0
        if groups[groupId] == nil {
            groups[groupId] = PlaybackGroup(
                id: groupId, isVoiceMode: payload.isVoiceMode,
                shouldPlay: phase != .stopping, generation: playbackGeneration)
            groupOrder.append(groupId)
            if activeGroupId == nil { activeGroupId = groupId }
        }
        guard var group = groups[groupId] else { return }
        group.chunks[chunkIndex] = AudioPlaybackChunk(
            id: payload.id, groupId: groupId, chunkIndex: chunkIndex,
            data: VoiceWire.decodeAudio(payload.audio), format: payload.format)
        if payload.isLastChunk == true { group.finalChunkIndex = chunkIndex }
        groups[groupId] = group
        exposeNextAudioChunk()
    }

    /// `transcription_result`: non-empty turns the phase to `.waiting`, empty returns to
    /// `.listening` (`onTranscriptionResult` upstream). The text itself goes into the
    /// timeline as the user's message; nothing is inserted into the draft here.
    public func handleTranscription(_ payload: TranscriptionResultPayload) {
        guard isVoiceMode else { return }
        if payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            turnInProgress = false
            if phase == .waiting { phase = .listening }
        } else {
            turnInProgress = true
            if phase != .playing { phase = .waiting }
        }
    }

    /// `voice_input_state`: server-side VAD. Speech interrupts playback — the whole
    /// queue resets and the engine is told to stop (`onServerSpeechStateChanged`).
    public func handleVoiceInputState(_ payload: VoiceInputStatePayload) {
        guard isVoiceMode else { return }
        isSpeaking = payload.isSpeaking
        if payload.isSpeaking {
            let shouldInterruptPlayback = phase == .playing || !groups.isEmpty
            resetPlaybackState()
            exposeNextAudioChunk()
            if shouldInterruptPlayback { playbackStopRequested &+= 1 }
            isAssistantAudioPlaying = false
        }
    }

    /// Turn events from `agent_stream`. Waiting/listening flips while never yanking the
    /// phase out from under playback (`onTurnEvent` upstream).
    public func handle(agentStream payload: AgentStreamPayload) {
        guard activeAgentId == payload.agentId, isVoiceMode else { return }
        switch payload.event {
        case .turnStarted:
            turnInProgress = true
            if phase != .playing { phase = .waiting }
        case .turnCompleted, .turnFailed, .turnCanceled:
            turnInProgress = false
            if phase != .playing { phase = .listening }
        default:
            break
        }
    }

    // MARK: Playback acknowledgement (UI -> store -> daemon)

    /// The engine finished (or failed) with `id`: advance the ordered cursor and ack
    /// with `audio_played` — but only when the chunk still belongs to this playback
    /// session. An ack arriving after stop/interrupt (the engine's in-flight
    /// completion) is stale: no crash, no ack (`generation !== playback.generation`
    /// early-return upstream).
    public func didPlayChunk(id: String) {
        guard advancePlayback(afterChunkId: id) else { return }
        let client = self.client
        Task {
            try? await client.send(AudioPlayed(id: id))
        }
    }

    /// A chunk the engine could not play at all still gets acked (upstream plays the
    /// catch path through the same ack).
    public func didFailChunk(id: String, error: Error? = nil) {
        lastPlaybackError = error.map(String.init(describing:))
        didPlayChunk(id: id)
    }

    // MARK: Connection lifecycle (HostSession)

    /// Called on every `server_info`; the readiness gate is read here and nowhere else.
    internal func serverInfoChanged(_ info: ServerInfo?) {
        readiness = info?.capabilities?.voice?.voice
        isVoiceAvailable = readiness?.isUsable == true
        unavailableReason = readiness?.unavailableMessage ?? ""
    }

    /// Socket state. A drop breaks the transport, clears the (socket-owned) playback and
    /// acks-in-flight state, and the next `.connected` re-issues `set_voice_mode`
    /// (`resyncVoiceMode` upstream).
    internal func handle(connection: ConnectionState) async {
        // The `.connected` resync is fire-and-forget (it must never gate the directory),
        // so its `set_voice_mode` round trip can land after the socket moved on. Every
        // state change bumps the generation; a stale response writes nothing.
        connectionGeneration &+= 1
        let generation = connectionGeneration
        switch connection {
        case .reconnecting:
            transportReady = false
            turnInProgress = false
            isSpeaking = false
            volume = 0
            resetPlaybackState()
            isAssistantAudioPlaying = false
            isVoiceSwitching = false
            exposeNextAudioChunk()
        case .failed, .idle, .connecting:
            // The socket is gone for good: full local teardown so the UI stops capture,
            // clears the wake lock and returns the composer to a normal state.
            transportReady = false
            turnInProgress = false
            playbackStopRequested &+= 1
            resetPlaybackState()
            isAssistantAudioPlaying = false
            clearCaptureTelemetry()
            activeAgentId = nil
            phase = .disabled
            isVoiceSwitching = false
            isMuted = false
            exposeNextAudioChunk()
        case .connected:
            guard isVoiceMode, let agentId = activeAgentId else { return }
            isVoiceSwitching = true
            do {
                let response = try await client.send(
                    SetVoiceModeRequest(enabled: true, agentId: agentId))
                guard generation == connectionGeneration else { return }
                if response.accepted {
                    transportReady = true
                    error = nil
                } else {
                    transportReady = false
                    error = voiceErrorText(response)
                }
            } catch let failure {
                guard generation == connectionGeneration else { return }
                transportReady = false
                error = String(describing: failure)
            }
            isVoiceSwitching = false
        }
    }

    // MARK: Internals

    /// The daemon client's error shape: the daemon's error plus its reason code in
    /// parentheses (`setVoiceMode` in `packages/client/src/daemon-client.ts`).
    private func voiceErrorText(_ response: SetVoiceModeRequest.Response) -> String {
        let base = response.error ?? "Failed to set voice mode"
        if let reasonCode = response.reasonCode?.trimmingCharacters(in: .whitespaces),
            !reasonCode.isEmpty
        {
            return "\(base) (\(reasonCode))"
        }
        return base
    }

    /// Clears the playback queue (interrupt, stop, resync). The engine hears about it
    /// through `playbackStopRequested`.
    private func resetPlaybackState() {
        playbackGeneration &+= 1
        groups = [:]
        groupOrder = []
        activeGroupId = nil
        nextAudioChunk = nil
    }

    private func clearCaptureTelemetry() {
        isSpeaking = false
        volume = 0
    }

    /// Surfaces the active group's next chunk, starting an unstarted voice group
    /// (`onAssistantAudioStarted` upstream: phase `.playing`).
    private func exposeNextAudioChunk() {
        guard let activeGroupId, var group = groups[activeGroupId],
            group.generation == playbackGeneration
        else {
            nextAudioChunk = nil
            return
        }
        guard group.shouldPlay else {
            nextAudioChunk = nil
            return
        }
        guard let chunk = group.chunks[group.nextChunkToPlay] else {
            nextAudioChunk = nil
            return
        }
        if group.shouldPlay, !group.started, group.isVoiceMode {
            group.started = true
            groups[activeGroupId] = group
            isAssistantAudioPlaying = true
            if phase != .stopping { phase = .playing }
        }
        nextAudioChunk = chunk
    }

    /// Ack-advanced cursor; retires a group once its final chunk played and acks
    /// (`retireFinishedGroup` upstream: playback finished → `listening`/`waiting`).
    /// Returns false when the ack is stale (unknown or previous-generation chunk).
    @discardableResult
    private func advancePlayback(afterChunkId: String) -> Bool {
        guard let activeGroupId, var group = groups[activeGroupId],
            group.generation == playbackGeneration,
            group.chunks[group.nextChunkToPlay]?.id == afterChunkId
        else { return false }
        group.chunks.removeValue(forKey: group.nextChunkToPlay)
        group.nextChunkToPlay += 1
        let finished: Bool
        if let finalChunkIndex = group.finalChunkIndex {
            finished = group.nextChunkToPlay > finalChunkIndex
        } else {
            finished = false
        }
        groups[activeGroupId] = group
        if finished {
            let wasStarted = group.started
            groups.removeValue(forKey: group.id)
            if groupOrder.first == group.id { groupOrder.removeFirst() }
            else { groupOrder.removeAll { $0 == group.id } }
            self.activeGroupId = groupOrder.first
            if wasStarted, group.isVoiceMode {
                isAssistantAudioPlaying = false
                if turnInProgress { phase = .waiting } else { phase = .listening }
            }
        }
        exposeNextAudioChunk()
        return true
    }
}
