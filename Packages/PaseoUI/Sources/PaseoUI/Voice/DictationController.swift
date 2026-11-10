#if canImport(UIKit)
import AVFoundation
import Speech
import SwiftUI

/// M8d: on-device dictation (`SFSpeechRecognizer` + `AVAudioEngine`), wired into the composer.
///
/// Prefers `requiresOnDeviceRecognition` when the recognizer supports it; requests Speech
/// Recognition and Microphone permissions only on first use; stops on send, when the app leaves
/// the foreground, and after ~2 s of silence. Partial results rewrite the dictation portion of
/// the draft live (revisions included); the host gets the whole draft through `onDraft`.
@MainActor @Observable
final class DictationController: NSObject {
    private(set) var isListening = false
    /// Permissions were denied (or no recognizer for the locale). Inline note in the composer.
    private(set) var isDenied = false
    /// Smoothed 0…1 from the input tap; drives the quiet mic pulse and the overlay meter.
    private(set) var level: Float = 0
    /// The dictation's live levels (D2 §4), drawn by `LiveWaveform` in the overlay.
    let waveform = LiveWaveformBuffer()
    /// Seconds since recording started; the overlay's `mm:ss` timer.
    private(set) var duration: TimeInterval = 0

    /// The host assigns this once and mirrors the emitted text into the draft verbatim.
    var onDraft: ((String) -> Void)?

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var sessionBase = ""
    private var committed = ""
    private var currentPartial = ""
    private var lastHeard = Date()
    private var startedAt = Date()
    /// Set once the recognizer returns any text; before that, silence is "not started yet".
    private var hasHeardSpeech = false
    private var silenceTask: Task<Void, Never>?
    /// The previous session teardown, kept so a new recording never activates the session while
    /// an older `setActive(false)` is still in flight.
    private var pendingDeactivation: Task<Void, Never>?

    /// Toggles listening. `currentDraft` snapshots what was already typed.
    func toggle(currentDraft: String) {
        if isListening {
            stop(keepingDraft: true)
        } else {
            Task { await start(currentDraft: currentDraft) }
        }
    }

    private func start(currentDraft: String) async {
        // Permission prompts on first use only.
        let speechAuthorized = await Self.requestSpeechAuthorization()
        let recordAuthorized = await AVAudioApplication.requestRecordPermission()
        guard speechAuthorized, recordAuthorized else {
            isDenied = true
            return
        }
        isDenied = false

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable
        else {
            isDenied = true
            return
        }

        sessionBase = currentDraft
        committed = ""
        currentPartial = ""
        duration = 0

        let engine = AVAudioEngine()
        let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
        bufferRequest.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            bufferRequest.requiresOnDeviceRecognition = true
        }

        // `setCategory` and `setActive` block on the audio server; on the main actor that is a
        // hang-risk fault (Xcode). The helpers are nonisolated statics, so they run off-main.
        await pendingDeactivation?.value
        pendingDeactivation = nil
        do {
            try await Self.activateSession()
        } catch {
            isDenied = true
            return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        Self.installLevelTap(on: input, format: format, request: bufferRequest) { [weak self] level in
            Task { @MainActor in
                self?.updateLevel(level)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            removeTapAndDeactivate(engine)
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
        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.duration = Date().timeIntervalSince(self.startedAt)
                // Before any words: wait up to 8 s for the user to start. After: 2.5 s of quiet ends it.
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
        guard isListening || engine != nil else { return }
        let base = sessionBase
        stop(keepingDraft: false)
        onDraft?(base)
    }

    /// Stops recording, keeping the draft text (partial output committed).
    func stop(keepingDraft: Bool) {
        // Not dictating: nothing to stop, and emitting here would overwrite the typed draft
        // with the (empty) dictation snapshot — send() calls this before reading the draft.
        guard isListening || engine != nil else { return }
        silenceTask?.cancel()
        silenceTask = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        request?.endAudio()
        recognition?.cancel()
        engine = nil
        request = nil
        recognition = nil
        isListening = false
        level = 0
        waveform.reset()
        duration = 0
        // Off-main, like activation: `setActive(false)` waits on the audio server too.
        pendingDeactivation = Task { await Self.deactivateSession() }
        if keepingDraft { emitDraft() }
    }

    private func removeTapAndDeactivate(_ engine: AVAudioEngine) {
        engine.inputNode.removeTap(onBus: 0)
        pendingDeactivation = Task { await Self.deactivateSession() }
        isListening = false
        level = 0
        waveform.reset()
        duration = 0
    }

    private func updateLevel(_ raw: Float) {
        // `measurement` mode has AGC off, so raw RMS sits around 0.005–0.03: map it into the
        // speech band, then ease it (attack 0.6, release 0.15) so the bars move with the words
        // instead of creeping along the floor (D2 §4).
        let target = AudioLevel.normalized(rms: raw)
        level = AudioLevel.smoothed(level, towards: target)
        waveform.push(level)
        if raw > 0.012 { lastHeard = Date() }
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

    nonisolated private static func deactivateSession() async {
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func installLevelTap(
        on input: AVAudioInputNode, format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest,
        onLevel: @escaping @Sendable (Float) -> Void
    ) {
        nonisolated(unsafe) let request = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            request.append(buffer)
            onLevel(rms(buffer))
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
#endif
