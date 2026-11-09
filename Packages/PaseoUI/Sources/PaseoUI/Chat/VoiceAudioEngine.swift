#if canImport(UIKit)
import AVFoundation
import Foundation
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
    /// Fired per input buffer with the sample level; the store smooths/publishes it.
    var onVolumeLevel: (Double) -> Void = { _ in }
    /// Fired when the OS interrupts the audio route (call, route change, Siri).
    var onInterruption: () -> Void = {}

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// The thinking tone gets its own node: it must never sit in the TTS queue or touch a
    /// chunk's `audio_played` ack.
    private let cuePlayer = AVAudioPlayerNode()
    private var cueTask: Task<Void, Never>?
    private var isCapturing = false
    private var playerAttached = false
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

    /// Capture DSP runs off the main actor: the tap only copies samples, the pipeline
    /// converts them and reports back on the main actor.
    private lazy var capturePipeline = VoiceCapturePipeline { [weak self] level, pcm in
        Task { @MainActor in
            guard let self else { return }
            self.onVolumeLevel(level)
            if !pcm.isEmpty { self.onCapturePCM(pcm) }
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
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func deactivateSessionOffMain() async {
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
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

    private func ensureEngineRunning() throws {
        guard connectPlaybackGraph() else {
            throw Self.engineError("Voice playback is unavailable on this device.")
        }
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
        guard !isCapturing else { return }
        try await activateSession()
        installInputTap()
        do {
            try ensureEngineRunning()
        } catch {
            // The tap must not survive a failed start: the next start would throw on
            // a reused tap (and record during a dead engine).
            engine.inputNode.removeTap(onBus: 0)
            throw error
        }
        isCapturing = true
        observeAudioEvents()
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Capture ending takes playback with it: `engine.stop()` fires the in-flight
        // schedule completion, and that must not restart the engine on a session we are
        // about to deactivate.
        stopPlayback()
        removeInterruptionObservers()
        // Voice has ended: release the session even if playback was active — otherwise
        // the `.playAndRecord` session (and the user's background music) stay hijacked.
        deactivateSession()
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
    }

    /// Route change: the input device or its format may have changed, so the old tap would
    /// deliver silence or a format the converter can't use. Reinstall it.
    private func reinstallTapForRouteChange() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try ensureEngineRunning()
            installInputTap()
        } catch {
            // A failed restart leaves capture dead; the user sees the mic not working
            // and can stop/start voice mode, which rebuilds the whole session.
        }
    }

    private func handleInterruption(
        type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions
    ) {
        switch type {
        case .began:
            stopPlayback()
            onInterruption()
        case .ended:
            // Only resume when the system says so (call ended and media was playing).
            if options.contains(.shouldResume) {
                Task { [weak self] in
                    guard let self else { return }
                    try? await self.activateSession()
                    if self.isCapturing { try? self.ensureEngineRunning() }
                    if self.playerAttached { self.player.play() }
                }
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
    }

    private func drainQueue() {
        guard !isPlayingNow, let next = playbackQueue.first else { return }
        do {
            try ensureEngineRunning()
        } catch {
            next.completion(false)
            return
        }
        playbackQueue.removeFirst()
        guard let buffer = playbackBuffer(data: next.data, format: next.format) else {
            next.completion(false)
            drainQueue()
            return
        }
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

/// Capture DSP that must not run on the main actor: copies each tap buffer, computes the
/// level, and converts to the 16 kHz int16 mono PCM the daemon expects. One serial queue,
/// one cached converter per input format.
final class VoiceCapturePipeline: @unchecked Sendable {
    static let uploadSampleRate = 16_000.0

    private let queue = DispatchQueue(label: "paseo.voice.capture", qos: .userInitiated)
    private let onChunk: @Sendable (Double, Data) -> Void
    private let converter = VoiceFormatConverter()
    private let uploadFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: VoiceCapturePipeline.uploadSampleRate,
        channels: 1, interleaved: true)

    /// `onChunk` receives the level and the PCM from the capture queue, in capture order.
    init(onChunk: @escaping @Sendable (Double, Data) -> Void) {
        self.onChunk = onChunk
    }

    /// Called on the audio thread. The engine reuses `buffer` as soon as this returns, so
    /// the samples are copied here; everything else runs on the serial queue.
    func capture(_ buffer: AVAudioPCMBuffer) {
        guard let frame = Frame(buffer) else { return }
        queue.async { [weak self] in
            guard let self, let result = self.process(frame) else { return }
            self.onChunk(result.level, result.pcm)
        }
    }

    private func process(_ frame: Frame) -> (level: Double, pcm: Data)? {
        guard let upload = uploadFormat,
            let inputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: frame.sampleRate,
                channels: AVAudioChannelCount(frame.channels.count), interleaved: false),
            let source = AVAudioPCMBuffer(
                pcmFormat: inputFormat, frameCapacity: frame.frameLength),
            let destination = source.floatChannelData
        else { return nil }
        source.frameLength = frame.frameLength
        for (index, channel) in frame.channels.enumerated() {
            channel.withUnsafeBufferPointer { samples in
                guard let base = samples.baseAddress else { return }
                destination[index].update(from: base, count: Int(frame.frameLength))
            }
        }
        let level = Self.level(frame.channels.first ?? [])
        guard let converted = converter.convert(source, to: upload),
            let pcm = converted.int16ChannelData
        else { return (level, Data()) }
        return (level, Data(bytes: pcm, count: Int(converted.frameLength) * 2))
    }

    private static func level(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return Double((sum / Float(samples.count)).squareRoot())
    }

    /// Copy of one tap buffer, detached from the engine's storage.
    private struct Frame: Sendable {
        var sampleRate: Double
        var frameLength: AVAudioFrameCount
        var channels: [[Float]]

        init?(_ buffer: AVAudioPCMBuffer) {
            let length = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            // The input node delivers deinterleaved float32; `floatChannelData[i]` for an
            // interleaved buffer would be one pointer into the whole thing, so bail out.
            guard length > 0, channelCount > 0, !buffer.format.isInterleaved,
                let data = buffer.floatChannelData
            else { return nil }
            var channels: [[Float]] = []
            channels.reserveCapacity(channelCount)
            for index in 0..<channelCount {
                channels.append(Array(UnsafeBufferPointer(start: data[index], count: length)))
            }
            self.sampleRate = buffer.format.sampleRate
            self.frameLength = buffer.frameLength
            self.channels = channels
        }
    }
}

/// One-shot buffer conversion with a converter cached per input format. Not thread-safe:
/// each instance is confined to one queue or actor.
final class VoiceFormatConverter {
    private var converters: [String: AVAudioConverter] = [:]

    /// Converts `input` into `outputFormat`. The input block hands the buffer over once
    /// and then reports end of stream, so `convert` can only return `.haveData`,
    /// `.inputRanDry` (output not full yet) or `.endOfStream` — all of them mean the
    /// output holds usable samples.
    func convert(_ input: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        let key = Self.key(input.format)
        let converter: AVAudioConverter
        if let cached = converters[key] {
            cached.reset()
            converter = cached
        } else {
            guard let created = AVAudioConverter(from: input.format, to: outputFormat) else {
                return nil
            }
            if converters.count > 8 { converters.removeAll() }
            converters[key] = created
            converter = created
        }
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let frames = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up))
        guard frames > 0,
            let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frames)
        else { return nil }
        let handoff = InputHandoff()
        let status = converter.convert(
            to: output, error: nil,
            withInputFrom: { _, outStatus in
                guard let next = handoff.take(input) else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return next
            })
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    private static func key(_ format: AVAudioFormat) -> String {
        "\(format.sampleRate)|\(format.channelCount)|\(format.commonFormat.rawValue)"
            + "|\(format.isInterleaved)"
    }
}

/// One-buffer handoff: the converter keeps asking for input until the output is full, so
/// the second request must report end of stream.
private final class InputHandoff {
    private var used = false
    func take(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard !used else { return nil }
        used = true
        return buffer
    }
}

/// Once-only continuation resume for a scheduled buffer (thinking tone, test tone): the
/// render completion and the safety timeout race, and exactly one of them resumes the
/// caller.
final class PlaybackCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    func attach(_ cont: CheckedContinuation<Void, Never>) {
        lock.lock()
        if finished { lock.unlock(); cont.resume(); return }
        continuation = cont
        lock.unlock()
    }

    func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume()
    }
}
#endif
