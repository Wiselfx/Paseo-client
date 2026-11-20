#if canImport(UIKit)
import AVFoundation
import Foundation
import OSLog
import PaseoStore

/// M15: realtime voice audio engine: records via `AVAudioEngine` + `.voiceChat`, converts
/// taps to 16 kHz 16-bit mono PCM (`audio/pcm;rate=16000;bits=16`) for `VoiceModeSession`,
/// and plays daemon `audio_output` chunks (PCM16 at the wire rate, or mp3) through a queued
/// player node, calling back when each chunk finishes so the store can ack it.
///
/// Mic permission reuses the dictation flow (asked on first use, same prompt).
/// Apple-only; parse-checked only, so every call here needs an Xcode pass.
@MainActor
final class VoiceAudioEngine {
    /// Fired per converted mic chunk, in capture order.
    var onCapturePCM: (Data) -> Void = { _ in }
    /// Fired per input buffer with the eased 0…1 mic level; the store smooths/publishes it.
    var onVolumeLevel: (Double) -> Void = { _ in }
    /// Fired when the OS interrupts the audio route (call, route change, Siri).
    var onInterruption: () -> Void = {}

    /// Voice mode's levels (D2 §4): the composer's bars read it, and the store's 0…1 telemetry
    /// is fed from the same eased value, so the meter and the accessibility percentage agree.
    let waveform: LiveWaveformBuffer
    /// Maps and eases every captured buffer on the capture queue, straight into `waveform`.
    let meter: AudioLevelMeter

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// The thinking tone gets its own node: it must never sit in the TTS queue or touch a
    /// chunk's `audio_played` ack.
    private let cuePlayer = AVAudioPlayerNode()
    private var cueTask: Task<Void, Never>?
    private var isCapturing = false
    /// Between the tap on the primary and `engine.start()` returning. A second start must not
    /// install a second tap (AVFoundation raises on that, it does not stack).
    private var isStarting = false
    /// The input tap is installed, so removing it is safe (removing a tap that was never
    /// installed raises).
    private var tapInstalled = false
    /// Bumped by every stop; a start that is still awaiting the session compares it after each
    /// await and tears its own half-built capture down instead of going live.
    private var captureGeneration = 0
    /// `setVoiceProcessingEnabled` is a one-way, expensive graph change: remember it.
    private var voiceProcessingEnabled = false
    private var playerAttached = false
    private var hasLoggedPlaybackStart = false
    /// The AEC warm-up window is armed once per voice session (reset in `startCapture`).
    private var hasArmedInputWarmup = false
    private var interruptionObservers: [NSObjectProtocol] = []
    private var playbackQueue: [QueuedChunk] = []
    private var isPlayingNow = false
    private var nextNodeID = 0
    /// The chunk the player is rendering. The schedule completion is `@Sendable`, so it
    /// captures the node id only and reads the completion back here on the main actor.
    private var inFlight: (nodeID: Int, completion: (Bool) -> Void)?
    /// The previous `setActive(false)`, awaited before the next activation so an old teardown
    /// can never land on a session we just turned on.
    private var pendingDeactivation: Task<Void, Never>?
    private let playbackConverter = VoiceFormatConverter()

    /// Everything the player node plays is converted into this one format, and the node is
    /// connected with it. `scheduleBuffer` neither resamples nor remixes: a buffer whose
    /// sample rate or channel count differs from the node's output bus plays at the wrong
    /// speed or fails to schedule, so "connect with nil and let the engine convert" is not
    /// a thing. Mono float32 at the daemon's TTS rate.
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)

    private struct QueuedChunk {
        var id: String
        var data: Data
        var format: String
        var completion: (Bool) -> Void
    }

    init() {
        let buffer = LiveWaveformBuffer()
        waveform = buffer
        meter = AudioLevelMeter(band: .voiceChat, buffer: buffer)
    }

    /// Capture DSP runs off the main actor: the tap only copies samples, the pipeline converts
    /// them, maps the level into the ring, and reports the chunk on the main actor at most 30
    /// times a second (H1 §3).
    private lazy var capturePipeline = VoiceCapturePipeline(meter: meter) {
        [weak self] level, pcm in
        Task { @MainActor in
            guard let self else { return }
            if !pcm.isEmpty { self.onCapturePCM(pcm) }
            self.onVolumeLevel(level)
        }
    }

    // MARK: Permissions + session

    /// Throws unless mic recording was granted (asks first, like dictation).
    func requestMicPermission() async throws {
        // AVAudioApplication (iOS 17+) replaces the deprecated AVAudioSession permission API.
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .undetermined:
            if await AVAudioApplication.requestRecordPermission() { return }
            throw Self.micDenied
        case .denied:
            throw Self.micDenied
        @unknown default:
            return
        }
    }

    private static var micDenied: NSError {
        NSError(
            domain: "paseo.voice", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Microphone permission is required to capture audio. Please enable microphone access in system settings."])
    }

    private func activateSession() async throws {
        await pendingDeactivation?.value
        pendingDeactivation = nil
        try await Self.activateSessionOffMain()
    }

    private func deactivateSession() {
        pendingDeactivation = Task { await Self.deactivateSessionOffMain() }
    }

    // MARK: Off-main session calls
    //
    // `setCategory`/`setActive` wait on the audio server; on the main actor that is an Xcode
    // hang-risk fault. Nonisolated statics put the calls on the cooperative pool.

    nonisolated private static func activateSessionOffMain() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord, mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
        // Upstream asks for 16 kHz (`AudioEngine.setupAudioSession`), the rate the daemon reads.
        // The hardware may ignore it; the capture converter handles whatever it gives us.
        try? session.setPreferredSampleRate(16_000)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func deactivateSessionOffMain() async {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        // `.voiceChat` must not outlive the voice session: it is a `.playAndRecord` category, so
        // every later sound the app makes would go through the voice-processing chain (and the
        // receiver) instead of the normal route. Same reason as `DictationController`.
        try? session.setCategory(.ambient, options: [.mixWithOthers])
    }

    // MARK: Graph

    /// The session is shared by capture and playback; the player is attached and connected
    /// exactly once, with `playbackFormat`. The `!isRunning` check in
    /// `ensureEngineRunning()` is what makes playback happen at all — scheduling into a
    /// stopped engine never plays.
    private func connectPlaybackGraph() -> Bool {
        if playerAttached { return true }
        guard let format = playbackFormat else { return false }
        engine.attach(player)
        engine.attach(cuePlayer)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.connect(cuePlayer, to: engine.mainMixerNode, format: format)
        playerAttached = true
        return true
    }

    /// The graph, without starting it: the playback nodes, then the input node's voice
    /// processing. Order matters — enabling voice processing reconfigures the input node, so the
    /// tap must be installed (with the node's *current* output format) afterwards.
    private func prepareGraph() throws {
        guard connectPlaybackGraph() else {
            throw Self.engineError("Voice playback is unavailable on this device.")
        }
        enableVoiceProcessing()
    }

    /// `setVoiceProcessingEnabled` reconfigures the IO unit's hardware chain and is the longest
    /// block in this file (Xcode flags it as a main-actor hang risk). It only ever runs on a
    /// stopped engine, before the tap exists, so nothing else touches the graph while it runs;
    /// `stopCapture` during a start only bumps the generation and lets the start unwind itself.
    /// The playback path (`prepareGraph`) keeps the main-actor variant: by the time audio plays,
    /// capture has already latched it.
    private func enableVoiceProcessingOffMain() async {
        guard !voiceProcessingEnabled else { return }
        nonisolated(unsafe) let input = engine.inputNode
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try input.setVoiceProcessingEnabled(true)
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            voiceProcessingEnabled = true
            // Upstream mutes the voice-processing input whenever it is not recording, so a lane
            // that only plays audio never holds the mic open.
            setVoiceProcessingInputMuted(true)
            VoiceLog.log.info("capture: voice processing (AEC) enabled")
        } catch {
            let nsError = error as NSError
            VoiceLog.log.error(
                "capture: voice processing unavailable, continuing without AEC — \(nsError.domain, privacy: .public) \(nsError.code)")
        }
    }

    /// Echo cancellation (E1 §3.3). Without it the speaker's audio comes back through the mic:
    /// the daemon's VAD hears "speech" the whole time a reply plays, `voice_input_state` stops
    /// playback on every chunk, and the transcriber hears the assistant instead of the user.
    /// Upstream enables it on the input node (`expo-two-way-audio` `AudioEngine.setup`).
    private func enableVoiceProcessing() {
        guard !voiceProcessingEnabled else { return }
        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
            voiceProcessingEnabled = true
            // Upstream mutes the voice-processing input whenever it is not recording
            // (`AudioEngine.setup`), so a lane that only plays audio never holds the mic open.
            setVoiceProcessingInputMuted(true)
            VoiceLog.log.info("capture: voice processing (AEC) enabled")
        } catch {
            let nsError = error as NSError
            VoiceLog.log.error(
                "capture: voice processing unavailable, continuing without AEC — \(nsError.domain, privacy: .public) \(nsError.code)")
        }
    }

    /// The mic is only open while we record. Playback (a reply, the thinking tone) keeps the
    /// engine running with the input muted, like upstream's `isVoiceProcessingInputMuted`.
    private func setVoiceProcessingInputMuted(_ muted: Bool) {
        guard voiceProcessingEnabled else { return }
        engine.inputNode.isVoiceProcessingInputMuted = muted
    }

    private func ensureEngineRunning() throws {
        try prepareGraph()
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private static func engineError(_ message: String) -> NSError {
        NSError(
            domain: "paseo.voice", code: 3,
            userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: Capture

    func startCapture() async throws {
        guard !isCapturing, !isStarting else { return }
        isStarting = true
        captureGeneration += 1
        let generation = captureGeneration
        VoiceLog.log.info("capture: start")
        do {
            try await activateSession()
            guard generation == captureGeneration else {
                // Stopped while the session was coming up: give it straight back.
                pendingDeactivation = Task { await Self.deactivateSessionOffMain() }
                isStarting = false
                return
            }
            VoiceLog.log.info("capture: session active (.playAndRecord/.voiceChat)")
            guard connectPlaybackGraph() else {
                throw Self.engineError("Voice playback is unavailable on this device.")
            }
            // The blocking half of `prepareGraph`, off the main actor: it changes the input
            // format, so it must finish before the tap's format is read.
            await enableVoiceProcessingOffMain()
            guard generation == captureGeneration else {
                // Stopped while the graph was being prepared: the session is already active,
                // so hand it back instead of leaving the mic open on a dead engine.
                isStarting = false
                pendingDeactivation = Task { await Self.deactivateSessionOffMain() }
                return
            }
            // A new session gets its own warm-up window: VPIO's canceller re-converges every
            // time capture starts, and a deadline left over from the last session must not drop
            // this one's first audio. Queued before the tap can deliver anything (E1b).
            hasArmedInputWarmup = false
            capturePipeline.resetWarmupWindow()
            installInputTap()
            try engine.start()
            guard generation == captureGeneration else {
                // The user stopped during `engine.start()`. This engine is ours to release.
                removeInputTap()
                engine.stop()
                isStarting = false
                pendingDeactivation = Task { await Self.deactivateSessionOffMain() }
                return
            }
            setVoiceProcessingInputMuted(false)
            VoiceLog.log.info("capture: engine started")
        } catch {
            let nsError = error as NSError
            VoiceLog.log.error(
                "capture: start failed — \(nsError.domain, privacy: .public) \(nsError.code): \(nsError.localizedDescription, privacy: .public)")
            // The tap must not survive a failed start: the next start would throw on a reused
            // tap (and record during a dead engine). `tapInstalled` keeps this from removing a
            // tap that was never installed, which raises inside AVFoundation.
            removeInputTap()
            engine.stop()
            isStarting = false
            // A start that failed after activation used to leave `.playAndRecord` active with
            // nothing recording: the mic indicator stayed lit and later audio stayed ducked.
            pendingDeactivation = Task { await Self.deactivateSessionOffMain() }
            throw error
        }
        isStarting = false
        isCapturing = true
        MicrophoneSessionOwner.voiceCaptureActive = true
        observeAudioEvents()
    }

    func stopCapture() {
        guard isCapturing || isStarting || tapInstalled else { return }
        captureGeneration += 1
        isStarting = false
        guard isCapturing else {
            // A stop that lands during `.starting`: `startCapture` sees the generation change
            // and releases what it built. Nothing else to do here.
            return
        }
        isCapturing = false
        VoiceLog.log.info("capture: stop")
        setVoiceProcessingInputMuted(true)
        meter.reset()
        removeInputTap()
        engine.stop()
        MicrophoneSessionOwner.voiceCaptureActive = false
        // Capture ending takes playback with it: `engine.stop()` fires the in-flight
        // schedule completion, and that must not restart the engine on a session we are
        // about to deactivate.
        stopPlayback()
        removeInterruptionObservers()
        // Voice has ended: release the session even if playback was active — otherwise
        // the `.playAndRecord` session (and the user's background music) stay hijacked.
        deactivateSession()
    }

    /// Removes the input tap only when one is installed (removing a tap that was never installed
    /// raises inside AVFoundation), and only once.
    private func removeInputTap() {
        guard tapInstalled else { return }
        tapInstalled = false
        engine.inputNode.removeTap(onBus: 0)
    }

    /// The tap block only copies: the buffer is reused by the engine as soon as the block
    /// returns, and all conversion happens on the pipeline's own queue.
    private func installInputTap() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let pipeline = capturePipeline
        // Explicitly @Sendable: a closure formed in this @MainActor class would otherwise be
        // main-actor isolated, and Swift 6's runtime check traps when the audio thread calls it.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in
            pipeline.capture(buffer)
        }
        tapInstalled = true
    }

    /// Route change: the input device or its format may have changed, so the old tap would
    /// deliver silence or a format the converter can't use. Reinstall it.
    private func reinstallTapForRouteChange() {
        guard isCapturing else { return }
        VoiceLog.log.info("capture: route changed, reinstalling the tap")
        removeInputTap()
        engine.stop()
        do {
            try prepareGraph()
            installInputTap()
            try engine.start()
        } catch {
            // A failed restart leaves capture dead; the user sees the mic not working
            // and can stop/start voice mode, which rebuilds the whole session.
            let nsError = error as NSError
            VoiceLog.log.error(
                "capture: tap reinstall failed — \(nsError.domain, privacy: .public) \(nsError.code)")
        }
    }

    private func handleInterruption(
        type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions
    ) {
        switch type {
        case .began:
            VoiceLog.log.info("interruption: began, playback stopped and mic muted")
            stopPlayback()
            onInterruption()
        case .ended:
            // Only resume when the system says so (call ended and media was playing).
            if options.contains(.shouldResume) {
                VoiceLog.log.info("interruption: ended with shouldResume, restarting the lane")
                Task { [weak self] in
                    guard let self else { return }
                    try? await self.activateSession()
                    if self.isCapturing { try? self.ensureEngineRunning() }
                    if self.playerAttached { self.player.play() }
                }
            } else {
                VoiceLog.log.info("interruption: ended without shouldResume")
            }
        @unknown default:
            break
        }
    }

    private func observeAudioEvents() {
        guard interruptionObservers.isEmpty else { return }
        let center = NotificationCenter.default
        interruptionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                switch raw {
                case AVAudioSession.InterruptionType.began.rawValue:
                    self.handleInterruption(type: .began, options: [])
                case AVAudioSession.InterruptionType.ended.rawValue:
                    self.handleInterruption(
                        type: .ended,
                        options: AVAudioSession.InterruptionOptions(rawValue: optionsRaw))
                default:
                    break
                }
            }
        })
        interruptionObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reinstallTapForRouteChange()
            }
        })
    }

    private func removeInterruptionObservers() {
        for observer in interruptionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        interruptionObservers = []
    }

    // MARK: Playback (store drives order; engine just plays)

    /// Enqueues one chunk; `completion(true)` fires when it finished playing,
    /// `completion(false)` when it was dropped (stop/overflow in the store).
    func enqueue(_ chunk: VoiceModeSession.AudioPlaybackChunk, completion: @escaping (Bool) -> Void) {
        VoiceLog.log.debug(
            "playback: chunk \(chunk.id, privacy: .public) \(chunk.data.count) bytes \(chunk.format, privacy: .public)")
        playbackQueue.append(QueuedChunk(
            id: chunk.id, data: chunk.data, format: chunk.format, completion: completion))
        drainQueue()
    }

    /// Stops the in-flight chunk and drops the queue (interrupt / stop voice mode).
    func stopPlayback() {
        // The thinking tone is part of "playback" for interrupt/stop purposes: upstream
        // stops the cue on an interrupt, on server speech and on every local stop.
        stopThinkingTone()
        // Invalidate the in-flight completion: `player.stop()` fires it, and it must not
        // ack a chunk that was cut off or start the next one.
        nextNodeID += 1
        inFlight = nil
        for item in playbackQueue { item.completion(false) }
        playbackQueue = []
        player.stop()
        isPlayingNow = false
        hasLoggedPlaybackStart = false
    }

    private func drainQueue() {
        guard !isPlayingNow, let next = playbackQueue.first else { return }
        do {
            try ensureEngineRunning()
        } catch {
            let nsError = error as NSError
            VoiceLog.log.error(
                "playback: engine unavailable — \(nsError.domain, privacy: .public) \(nsError.code): \(nsError.localizedDescription, privacy: .public)")
            next.completion(false)
            return
        }
        playbackQueue.removeFirst()
        guard let buffer = playbackBuffer(data: next.data, format: next.format) else {
            VoiceLog.log.error(
                "playback: cannot decode \(next.format, privacy: .public), chunk dropped")
            next.completion(false)
            drainQueue()
            return
        }
        if !hasLoggedPlaybackStart {
            hasLoggedPlaybackStart = true
            VoiceLog.log.info(
                "playback: start \(next.format, privacy: .public), \(next.data.count) bytes")
        }
        armInputWarmupIfNeeded(.reply)
        isPlayingNow = true
        nextNodeID += 1
        let nodeID = nextNodeID
        inFlight = (nodeID, next.completion)
        player.scheduleBuffer(
            buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack
        ) { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self, nodeID == self.nextNodeID,
                    let finished = self.inFlight, finished.nodeID == nodeID
                else { return }
                self.inFlight = nil
                self.isPlayingNow = false
                finished.completion(true)
                self.drainQueue()
            }
        }
        player.play()
    }

    /// What started the window. Both are PCM on the speaker, so both are audio the mic can
    /// hear; the log line says which one armed it.
    private enum WarmupSource: String {
        case reply
        case cue
    }

    /// Upstream arms the AEC warm-up in `playPCMData`
    /// (`expo-two-way-audio/ios/AudioEngine.swift:248-253`), the one native path both the reply
    /// and the thinking cue take: the engine's first PCM playback drops the next two seconds of
    /// mic (`discardFirstInputMillis`, `:30`) so AEC can adapt.
    /// Dropped audio is not processed at all — no level, nothing sent (`:175-179`).
    ///
    /// Two differences from upstream, both on purpose (E1b): the window is per **voice session**
    /// (armed at each capture start, not once per engine or launch), and only armable while the
    /// mic is live — a chunk scheduled while capture is stopped must not consume it.
    private func armInputWarmupIfNeeded(_ source: WarmupSource) {
        guard isCapturing, !hasArmedInputWarmup else { return }
        hasArmedInputWarmup = true
        VoiceLog.log.info(
            "capture: AEC warm-up window armed by \(source.rawValue, privacy: .public) — dropping mic for \(VoiceCapturePipeline.warmupDiscardSeconds) s")
        capturePipeline.discardInput(
            until: Date().timeIntervalSince1970 + VoiceCapturePipeline.warmupDiscardSeconds)
    }

    /// Settings → Diagnostics "Test audio". Upstream plays the thinking-tone blob here
    /// (`handlePlaybackTest` in `settings-screen.tsx`), so this is the same asset and the
    /// same format, once. Always returns: starts and connects the engine, and a timeout
    /// just past the tone's length releases the caller even if the render completion
    /// never fires (stopped/unconnected engine).
    func playTestTone() async throws {
        guard let tone = thinkingTone else {
            throw Self.engineError("Could not load the audio test tone.")
        }
        // Upstream stops the engine before the test tone; do the same so it never queues
        // behind TTS chunks or the cue.
        stopPlayback()
        try ensureEngineRunning()
        let finished = PlaybackCompletion()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            finished.attach(cont)
            Task { try? await Task.sleep(for: .milliseconds(Int(tone.durationMs.rounded()) + 1_000)); finished.finish() }
            player.scheduleBuffer(
                tone.buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack
            ) { @Sendable _ in
                finished.finish()
            }
            player.play()
        }
    }

    // MARK: Thinking tone

    /// Upstream `THINKING_TONE_MIN_SILENCE_MS`: a reply is spoken one TTS segment per
    /// sentence, and those gaps are short; the cue is for a wait the user can't otherwise
    /// explain, so it only starts once the silence has outlasted them.
    private static let thinkingToneMinSilenceMs = 1_500
    /// Upstream `THINKING_TONE_REPEAT_GAP_MS`.
    private static let thinkingToneRepeatGapMs = 350
    /// Upstream's `audio/pcm;rate=16000;bits=16` cue asset.
    private static let thinkingToneSampleRate = 16_000.0

    private struct ThinkingTone {
        var buffer: AVAudioPCMBuffer
        var durationMs: Double
    }

    /// Upstream's `thinking-tone.native-pcm.ts` blob verbatim (16 kHz mono PCM16, 2.98 s,
    /// already attenuated to ≈ -22 dBFS — do not re-gain it), converted once into
    /// `playbackFormat`. Bundled as `Resources/thinking-tone.pcm`.
    private lazy var thinkingTone: ThinkingTone? = {
        guard let format = playbackFormat,
            let url = Bundle.module.url(forResource: "thinking-tone", withExtension: "pcm"),
            let data = try? Data(contentsOf: url),
            let sourceFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: Self.thinkingToneSampleRate,
                channels: 1, interleaved: true),
            let source = Self.pcm16Buffer(data: data, format: sourceFormat),
            let buffer = playbackConverter.convert(source, to: format)
        else { return nil }
        return ThinkingTone(
            buffer: buffer,
            durationMs: Double(data.count / 2) / Self.thinkingToneSampleRate * 1000)
    }()

    /// Starts the looping thinking tone (`reconcileCue` upstream): first tone after 1.5 s,
    /// then `duration + 350 ms` after each tone has finished playing. Idempotent while it
    /// is already running. The caller drives this from `VoiceModeSession.isThinkingToneExpected`.
    func startThinkingTone() {
        guard cueTask == nil, thinkingTone != nil else { return }
        cueTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(Self.thinkingToneMinSilenceMs))
                while true {
                    await self.playThinkingToneOnce()
                    guard let tone = self.thinkingTone else { return }
                    try await Task.sleep(
                        for: .milliseconds(
                            Int((tone.durationMs + Double(Self.thinkingToneRepeatGapMs)).rounded())))
                }
            } catch {
                // Cancelled by `stopThinkingTone()`, which also stopped the cue player.
            }
        }
    }

    /// Stops it now: the reply started, the phase left `.waiting`, the user spoke, voice
    /// stopped or the connection went away.
    func stopThinkingTone() {
        cueTask?.cancel()
        cueTask = nil
        cuePlayer.stop()
    }

    /// One pass of the tone on the cue node, resolved when it finishes rendering (or the
    /// node is stopped by `stopThinkingTone()`).
    private func playThinkingToneOnce() async {
        guard let tone = thinkingTone else { return }
        guard (try? ensureEngineRunning()) != nil else { return }
        // The cue is PCM too, and upstream arms the window in the one `playPCMData` both the
        // cue and the reply go through (see `armInputWarmupIfNeeded`).
        armInputWarmupIfNeeded(.cue)
        let finished = PlaybackCompletion()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            finished.attach(cont)
            cuePlayer.scheduleBuffer(
                tone.buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack
            ) { @Sendable _ in
                finished.finish()
            }
            cuePlayer.play()
        }
    }

    // MARK: Decoding

    /// One daemon chunk in `playbackFormat`: `pcm` chunks are widened and rate-converted,
    /// mp3/wav are decoded and converted. Nil means "cannot play" (the store acks it
    /// through the failure path, exactly like a malformed base64 payload).
    private func playbackBuffer(data: Data, format: String) -> AVAudioPCMBuffer? {
        guard let output = playbackFormat else { return nil }
        let source = Self.describe(format)
        if source.isPCM {
            guard source.bits == 16 else { return nil }
            guard let sourceFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: source.sampleRate, channels: 1,
                interleaved: true),
                let buffer = Self.pcm16Buffer(data: data, format: sourceFormat)
            else { return nil }
            return playbackConverter.convert(buffer, to: output)
        }
        guard let decoded = Self.decodedFileBuffer(data: data, suffix: source.container) else {
            return nil
        }
        return playbackConverter.convert(decoded, to: output)
    }

    /// The wire format strings look like `audio/pcm;rate=24000;bits=16`, `pcm;rate=24000`
    /// or `audio/mpeg`. The rate is parsed, not assumed: a chunk's rate is whatever the
    /// daemon's TTS produced.
    private struct SourceFormat {
        var isPCM: Bool
        var sampleRate: Double
        var bits: Int
        var container: String
    }

    private static func describe(_ format: String) -> SourceFormat {
        let lower = format.lowercased()
        var sampleRate = 24_000.0
        var bits = 16
        for part in lower.split(whereSeparator: { $0 == ";" || $0 == "," }) {
            let piece = part.trimmingCharacters(in: .whitespaces)
            if piece.hasPrefix("rate=") {
                if let value = Double(piece.dropFirst(5)), value > 0 { sampleRate = value }
            } else if piece.hasPrefix("bits=") {
                if let value = Int(piece.dropFirst(5)), value > 0 { bits = value }
            }
        }
        return SourceFormat(
            isPCM: lower.contains("pcm"), sampleRate: sampleRate, bits: bits,
            container: lower.contains("wav") ? "wav" : "mp3")
    }

    /// Little-endian mono 16-bit PCM from the wire into a PCM buffer.
    private static func pcm16Buffer(data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = data.count / 2
        guard frames > 0,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
            let channel = buffer.int16ChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for index in 0..<frames {
                let low = UInt16(base.load(fromByteOffset: index * 2, as: UInt8.self))
                let high = UInt16(base.load(fromByteOffset: index * 2 + 1, as: UInt8.self))
                channel[index] = Int16(bitPattern: low | (high << 8))
            }
        }
        return buffer
    }

    /// mp3/wav chunks arrive as a whole file; decode it through a temp file.
    private static func decodedFileBuffer(data: Data, suffix: String) -> AVAudioPCMBuffer? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paseo-audio-\(UUID().uuidString).\(suffix)")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? data.write(to: url)) != nil,
            let file = try? AVAudioFile(forReading: url),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
            (try? file.read(into: buffer)) != nil
        else { return nil }
        return buffer
    }

}
#endif
