#if canImport(UIKit)
import AVFoundation
import PaseoStore
import Speech
import SwiftUI

/// M8d: on-device dictation (`SFSpeechRecognizer` + `AVAudioEngine`), wired into the composer.
///
/// Prefers `requiresOnDeviceRecognition` when the recognizer supports it; requests Speech
/// Recognition and Microphone permissions only on first use; stops on send, when the app leaves
/// the foreground, and after ~2 s of silence. Partial results rewrite the dictation portion of
/// the draft live (revisions included); the host gets the whole draft through `onDraft`.
///
/// The level never reaches the main actor: the tap maps it with `AudioLevelMeter` straight into
/// `waveform` on the audio thread (H1 §3), and the bars read it from their own display link.
@MainActor @Observable
final class DictationController: NSObject {
    private(set) var isListening = false
    /// True between the tap on the mic and the engine actually running. A second tap while this
    /// is set cancels the start instead of building a second engine (two taps on one input node
    /// is an exception, not a second recording).
    private(set) var isStarting = false
    /// Permissions were denied. Inline note in the composer, with a Settings action.
    private(set) var isDenied = false
    /// A start that failed for a reason other than permission (engine, session, recognizer).
    /// Inline note in the composer; nil once the user retries or dismisses it.
    private(set) var failure: Failure?

    /// The inline note's copy. The title is upstream `message.dictation.failed`'s prefix; the
    /// message is the system's own error description, never invented.
    struct Failure: Sendable, Equatable {
        var title: String
        var message: String
    }
    /// The dictation's live levels, drawn by `LiveWaveform` in the overlay.
    ///
    /// The only carrier of the level (E1 §2.4): a plain reference the renderer reads when it
    /// draws. An `@Observable` level here was read by the composer's body, so every audio buffer
    /// re-evaluated the whole composer.
    let waveform: LiveWaveformBuffer
    /// Maps and eases each tap buffer on the audio thread, into `waveform`.
    let meter: AudioLevelMeter
    /// One dB line a second, so a flat meter can be diagnosed from a log instead of a guess.
    private let levelLog = LevelLog()
    /// Seconds since recording started, to the whole second (the overlay's `mm:ss` timer).
    private(set) var duration: TimeInterval = 0

    /// The host assigns this once and mirrors the emitted text into the draft verbatim.
    var onDraft: ((String) -> Void)?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var sessionBase = ""
    @ObservationIgnored private var committed = ""
    @ObservationIgnored private var currentPartial = ""
    @ObservationIgnored private var lastHeard = Date()
    @ObservationIgnored private var startedAt = Date()
    /// Set once the recognizer returns any text; before that, silence is "not started yet".
    @ObservationIgnored private var hasHeardSpeech = false
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    /// The previous session teardown, kept so a new recording never activates the session while
    /// an older `setActive(false)` is still in flight.
    @ObservationIgnored private var pendingDeactivation: Task<Void, Never>?
    /// Bumped by every stop. A start that is still awaiting permissions or the session compares
    /// it after each await and tears its own half-built engine down instead of going live.
    @ObservationIgnored private var generation = 0
    /// The tap on the input node is installed (so removing it is safe; removing a tap that was
    /// never installed raises).
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var audioObservers: [NSObjectProtocol] = []

    override init() {
        let buffer = LiveWaveformBuffer()
        waveform = buffer
        meter = AudioLevelMeter(band: .dictation, buffer: buffer)
        super.init()
    }

    // MARK: Start / stop

    /// Toggles listening. `currentDraft` snapshots what was already typed.
    ///
    /// `isStarting` is raised here, synchronously, before the start hops to its Task: a second
    /// tap in the same frame must cancel the start (via the stop below), not queue a second one
    /// that the guard inside `start` then silently swallows.
    func toggle(currentDraft: String) {
        if isListening || isStarting {
            stop(keepingDraft: true)
        } else {
            isStarting = true
            Task { await start(currentDraft: currentDraft) }
        }
    }

    private func start(currentDraft: String) async {
        guard !isListening, isStarting else { return }
        failure = nil
        let generation = self.generation

        // Permission prompts on first use only.
        let speechAuthorized = await Self.requestSpeechAuthorization()
        guard generation == self.generation else { isStarting = false; return }
        let recordAuthorized = await AVAudioApplication.requestRecordPermission()
        guard generation == self.generation else { isStarting = false; return }
        guard speechAuthorized, recordAuthorized else {
            isStarting = false
            isDenied = true
            return
        }
        isDenied = false

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable
        else {
            isStarting = false
            failure = Failure(title: "Dictation", message: Self.unavailableMessage)
            return
        }

        sessionBase = currentDraft
        committed = ""
        currentPartial = ""
        duration = 0
        meter.reset()

        let engine = AVAudioEngine()
        let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
        bufferRequest.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            bufferRequest.requiresOnDeviceRecognition = true
        }

        // `setCategory` and `setActive` block on the audio server; on the main actor that is a
        // hang-risk fault (Xcode). The helpers are nonisolated statics, so they run off-main.
        await pendingDeactivation?.value
        guard generation == self.generation else { isStarting = false; return }
        pendingDeactivation = nil
        do {
            try await Self.activateSession()
        } catch {
            isStarting = false
            failure = Self.failure(for: error)
            return
        }
        guard generation == self.generation else {
            // Stopped while the session was coming up: give it straight back.
            pendingDeactivation = Task { await Self.deactivateSession() }
            isStarting = false
            return
        }

        installTap(on: engine, request: bufferRequest)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            tearDown(engine: engine, request: bufferRequest, recognition: nil)
            isStarting = false
            failure = Self.failure(for: error)
            return
        }

        guard generation == self.generation else {
            // Stopped while the engine was starting: it is ours to release.
            tearDown(engine: engine, request: bufferRequest, recognition: nil)
            isStarting = false
            return
        }

        self.engine = engine
        self.request = bufferRequest
        lastHeard = Date()
        startedAt = Date()
        hasHeardSpeech = false

        recognition = Self.startRecognition(recognizer, request: bufferRequest) {
            [weak self] text, isFinal, failed in
            Task { @MainActor in
                guard let self else { return }
                if let text { self.handle(text: text, isFinal: isFinal) }
                if failed || isFinal { self.stop(keepingDraft: true) }
            }
        }

        isListening = true
        isStarting = false
        observeAudioEvents()
        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                // Whole seconds only: the overlay's label reads `duration`, and writing a new
                // value twice a second would re-evaluate the composer for a digit that has not
                // changed.
                let whole = Date().timeIntervalSince(self.startedAt).rounded(.down)
                if whole != self.duration { self.duration = whole }
                // Before any words: wait up to 8 s for the user to start. After: 2.5 s of quiet.
                let limit: TimeInterval = self.hasHeardSpeech ? 2.5 : 8
                if Date().timeIntervalSince(self.lastHeard) > limit {
                    self.stop(keepingDraft: true)
                    return
                }
            }
        }
    }

    /// Cancels dictation and puts the draft back the way it was when recording started.
    func cancel() {
        guard isListening || isStarting || engine != nil else { return }
        let base = sessionBase
        stop(keepingDraft: false)
        onDraft?(base)
    }

    /// Stops recording, keeping the draft text (partial output committed).
    func stop(keepingDraft: Bool) {
        // Not dictating: nothing to stop, and emitting here would overwrite the typed draft
        // with the (empty) dictation snapshot — send() calls this before reading the draft.
        let wasRecording = isListening || isStarting || engine != nil
        guard wasRecording else { return }
        generation += 1
        isStarting = false
        silenceTask?.cancel()
        silenceTask = nil
        if let engine {
            tearDown(engine: engine, request: request, recognition: recognition)
        } else {
            removeAudioObservers()
        }
        engine = nil
        request = nil
        recognition = nil
        isListening = false
        duration = 0
        meter.reset()
        // Off-main, like activation: `setActive(false)` waits on the audio server too.
        pendingDeactivation = Task { await Self.deactivateSession() }
        if keepingDraft { emitDraft() }
    }

    /// Clears the inline failure note (the composer's dismiss/retry action).
    func dismissFailure() {
        failure = nil
    }

    /// One teardown for every failure path and for `stop`. Removing a tap that was never
    /// installed raises inside AVFoundation, so the flag guards it.
    private func tearDown(
        engine: AVAudioEngine, request: SFSpeechAudioBufferRecognitionRequest?,
        recognition: SFSpeechRecognitionTask?
    ) {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        request?.endAudio()
        recognition?.cancel()
        removeAudioObservers()
    }

    // MARK: Tap and level

    /// The tap delivers to the recognizer and to the meter. Nothing on this path touches the main
    /// actor: the level is mapped on the audio thread and written into `waveform`.
    private func installTap(
        on engine: AVAudioEngine, request: SFSpeechAudioBufferRecognitionRequest
    ) {
        let input = engine.inputNode
        // Read after the session is active: a format read before activation is 0 Hz on device
        // and the tap then delivers nothing.
        let format = input.outputFormat(forBus: 0)
        Self.installTap(
            on: input, format: format, request: request, meter: meter, levelLog: levelLog)
        tapInstalled = true
    }

    private func handle(text: String, isFinal: Bool) {
        if !text.isEmpty {
            hasHeardSpeech = true
            lastHeard = Date()
        }
        if isFinal {
            committed += (committed.isEmpty ? "" : " ") + text
            currentPartial = ""
        } else {
            currentPartial = text
        }
        emitDraft()
    }

    private func emitDraft() {
        let tail = (committed + currentPartial).trimmingCharacters(in: .whitespaces)
        var combined = sessionBase
        if !tail.isEmpty {
            if !combined.isEmpty, !combined.hasSuffix(" "), !combined.hasSuffix("\n") {
                combined += " "
            }
            combined += tail
        }
        onDraft?(combined)
    }

    // MARK: Interruptions and routes

    /// A call or Siri stops the recording and keeps what was heard; a microphone route change
    /// (AirPods in or out) kills the tap's format, so it ends there too rather than recording
    /// silence.
    private func observeAudioEvents() {
        guard audioObservers.isEmpty else { return }
        let center = NotificationCenter.default
        audioObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                guard let self else { return }
                guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                VoiceLog.log.info("dictation: interrupted, keeping the transcript")
                self.stop(keepingDraft: true)
            }
        })
        audioObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                guard let self else { return }
                switch raw {
                case AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
                    AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue:
                    VoiceLog.log.info("dictation: audio route changed, keeping the transcript")
                    self.stop(keepingDraft: true)
                default:
                    break
                }
            }
        })
    }

    private func removeAudioObservers() {
        for observer in audioObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        audioObservers = []
    }

    // MARK: Messages

    /// Upstream `message.dictation.failed` (`en.ts`): "Dictation failed: {{error}}" — the
    /// banner's title is that prefix, its message the system's description.
    private static func failure(for error: Error) -> Failure {
        Failure(
            title: "Dictation failed",
            message: (error as NSError).localizedDescription)
    }

    /// Proposed copy (see the ticket's final message): the recognizer is there but unusable.
    static let unavailableMessage = "Dictation is not available right now."

    // MARK: Off-main callbacks
    //
    // Speech and AVAudio call these closures on their own queues. A closure written inside
    // this @MainActor class would inherit main-actor isolation and trap at runtime when
    // called off the main thread, so they are formed in nonisolated static functions.

    nonisolated private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    /// Both calls block on the audio server. Nonisolated, so the body runs on the cooperative
    /// pool rather than the main actor.
    nonisolated private static func activateSession() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Never deactivates the session realtime voice is recording through (E1 §3): dictation's
    /// teardown is deferred, so it can land milliseconds after voice mode activated the same
    /// shared session — which killed the mic mid-conversation.
    nonisolated private static func deactivateSession() async {
        let voiceOwnsSession = await MainActor.run { MicrophoneSessionOwner.voiceCaptureActive }
        guard !voiceOwnsSession else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        // Give the app its idle category back. `.measurement` without `.defaultToSpeaker` would
        // otherwise outlive the recording: `SoundCues` builds its engine once and only sets
        // `.ambient` on that first build, so after a single dictation every cue (and anything
        // else playing through that engine) comes out of the earpiece at call volume.
        try? session.setCategory(.ambient, options: [.mixWithOthers])
    }

    nonisolated private static func installTap(
        on input: AVAudioInputNode, format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest, meter: AudioLevelMeter,
        levelLog: LevelLog
    ) {
        nonisolated(unsafe) let request = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            request.append(buffer)
            // One RMS on the audio thread, mapped and eased there, straight into the ring the
            // renderer reads. No main-actor hop per buffer (H1 §3).
            let level = rms(buffer)
            let eased = meter.push(rms: level)
            levelLog.log(rms: level, eased: eased)
        }
    }

    /// `onResult(text, isFinal, failed)` runs on the recognizer's queue.
    nonisolated private static func startRecognition(
        _ recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
        onResult: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { @Sendable result, error in
            onResult(
                result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    /// RMS of the first float channel — a level meter for the mic pulse.
    nonisolated static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let length = Int(buffer.frameLength)
        guard length > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<length {
            let sample = channel[index]
            sum += sample * sample
        }
        return sqrt(sum / Float(length))
    }
}

/// One dB line a second from the tap. The tap is not on the main actor, so the throttle is
/// lock-guarded rather than a property of the controller (H1 §1 asks for the raw numbers).
final class LevelLog: @unchecked Sendable {
    private let lock = NSLock()
    private var last: TimeInterval = 0

    func log(rms: Float, eased: Float, at now: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock()
        guard now - last >= 1 else {
            lock.unlock()
            return
        }
        last = now
        lock.unlock()
        let db = 20 * log10(max(rms, 1e-5))
        VoiceLog.log.debug(
            "dictation level db=\(String(format: "%.1f", db), privacy: .public) eased=\(String(format: "%.3f", eased), privacy: .public)")
    }

    func reset() {
        lock.lock()
        last = 0
        lock.unlock()
    }
}

/// Which subsystem owns the app's shared audio session (E1 §3).
///
/// Dictation and realtime voice both put `AVAudioSession` into `.playAndRecord`. Dictation's
/// teardown is deferred off-main and can land after voice mode has activated the same session,
/// so it reads this flag first and stands down instead of stopping the microphone mid-reply.
@MainActor
enum MicrophoneSessionOwner {
    /// True while `VoiceAudioEngine` is capturing.
    static var voiceCaptureActive = false
}
#endif
