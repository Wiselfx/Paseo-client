#if canImport(UIKit)
import AVFoundation
import Foundation
import PaseoStore

/// M15: realtime voice audio engine: records via `AVAudioEngine` + `.voiceChat`, converts
/// taps to 16 kHz 16-bit mono PCM (`audio/pcm;rate=16000;bits=16`) for `VoiceModeSession`,
/// and plays daemon `audio_output` chunks (24 kHz PCM16 or mp3) through a queued player
/// node, calling back when each chunk finishes so the store can ack it.
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
    private var isCapturing = false
    private var playerAttached = false
    private var interruptionObservers: [NSObjectProtocol] = []
    private var playbackQueue: [QueuedChunk] = []
    private var isPlayingNow = false
    private var nextNodeID = 0

    private struct QueuedChunk {
        var id: String
        var data: Data
        var format: String
        var completion: (Bool) -> Void
    }

    private static let pcmUploadSampleRate = 16_000.0

    // MARK: Permissions + session

    /// Throws unless mic recording was granted (asks first, like dictation).
    func requestMicPermission() async throws {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return
        case .undetermined:
            let granted = await withCheckedContinuation { cont in
                session.requestRecordPermission { cont.resume(returning: $0) }
            }
            if !granted {
                throw NSError(
                    domain: "paseo.voice", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Microphone permission is required to capture audio. Please enable microphone access in system settings."])
            }
        case .denied:
            throw NSError(
                domain: "paseo.voice", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone permission is required to capture audio. Please enable microphone access in system settings."])
        @unknown default:
            return
        }
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord, mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The session is shared by capture and playback, and the player is connected once
    /// to the main mixer (nil format: the engine auto-converts every scheduled buffer).
    /// The `!isRunning` check in `ensureEngineRunning()` is what makes playback happen
    /// at all — scheduling into a stopped engine never plays.
    private func connectPlaybackGraph() {
        guard !playerAttached else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        playerAttached = true
    }

    private func ensureEngineRunning() throws {
        connectPlaybackGraph()
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    func startCapture() throws {
        guard !isCapturing else { return }
        try activateSession()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            Task { @MainActor in
                guard let self else { return }
                let level = Self.rms(buffer)
                self.onVolumeLevel(Double(level))
                let pcm = Self.convertTo16kHzPCM(buffer)
                if let pcm, !pcm.isEmpty { self.onCapturePCM(pcm) }
            }
        }
        do {
            try ensureEngineRunning()
        } catch {
            // The tap must not survive a failed start: the next start would throw on
            // a reused tap (and record during a dead engine).
            input.removeTap(onBus: 0)
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
        removeInterruptionObservers()
        // Voice has ended: release the session even if playback was active — otherwise
        // the `.playAndRecord` session (and the user's background music) stay hijacked.
        deactivateSession()
    }

    /// Route/config change: the input device or its format may have changed, so the old
    /// tap would deliver silence or a format the converter can't use. Reinstall it.
    private func reinstallTapForRouteChange() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try ensureEngineRunning()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                Task { @MainActor in
                    guard let self else { return }
                    let level = Self.rms(buffer)
                    self.onVolumeLevel(Double(level))
                    let pcm = Self.convertTo16kHzPCM(buffer)
                    if let pcm, !pcm.isEmpty { self.onCapturePCM(pcm) }
                }
            }
        } catch {
            // A failed restart leaves capture dead; the user sees the mic not working
            // and can stop/start voice mode, which rebuilds the whole session.
        }
    }

    private func handleInterruption(type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            stopPlayback()
            onInterruption()
        case .ended:
            // Only resume when the system says so (call ended and media was playing).
            if options.contains(.shouldResume) {
                try? activateSession()
                if isCapturing { try? ensureEngineRunning() }
                player.play()
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
        guard let buffer = Self.playbackBuffer(data: next.data, format: next.format) else {
            next.completion(false)
            drainQueue()
            return
        }
        isPlayingNow = true
        nextNodeID += 1
        let nodeID = nextNodeID
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] in
            Task { @MainActor in
                guard let self, nodeID == self.nextNodeID else { return }
                self.isPlayingNow = false
                next.completion(true)
                self.drainQueue()
            }
        }
        player.play()
    }

    /// Settings → Diagnostics "Test audio": plays a quiet locally generated tone
    /// (upstream plays the thinking-tone PCM blob here). Always returns: starts and
    /// connects the engine, and a 3 s timeout releases the caller even if the render
    /// completion never fires (stopped/unconnected engine).
    func playTestTone() async throws {
        let buffer = try Self.makeTestTone()
        try ensureEngineRunning()
        let tone = TestToneCompletion()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            tone.attach(cont)
            Task { try? await Task.sleep(for: .seconds(3)); tone.finish() }
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) {
                tone.finish()
            }
            player.play()
        }
    }

    // MARK: Helpers

    /// 16-bit mono PCM bytes for a decoded buffer, emitted at the daemon's rate.
    /// `pcm` daemon chunks arrive at 24 kHz; `mp3` is decoded to its own rate.
    static func playbackBuffer(data: Data, format: String) -> AVAudioPCMBuffer? {
        switch format {
        case "pcm":
            guard let pcmFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1,
                interleaved: true)
            else { return nil }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(data.count / 2))
            else { return nil }
            buffer.frameLength = AVAudioFrameCount(data.count / 2)
            guard let destination = buffer.int16ChannelData else { return nil }
            data.withUnsafeBytes { raw in
                raw.copyBytes(to: destination, count: data.count)
            }
            return buffer
        default:
            // mp3 (or wav): decode to its native rate, then play via the same node.
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("paseo-audio-\(UUID().uuidString).mp3")
            guard (try? data.write(to: temp)) != nil,
                let file = try? AVAudioFile(forReading: temp),
                let format = file.processingFormat,
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
            else {
                try? FileManager.default.removeItem(at: temp)
                return nil
            }
            try? file.read(into: buffer)
            try? FileManager.default.removeItem(at: temp)
            return buffer
        }
    }

    /// Converts one tap buffer to 16 kHz int16 mono bytes, or nil when the device's
    /// format can't convert (the store just drops the chunk).
    static func convertTo16kHzPCM(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let to = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: pcmUploadSampleRate, channels: 1,
            interleaved: true),
            let converter = AVAudioConverter(from: buffer.format, to: to)
        else { return nil }

        let ratio = to.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 8
        guard let output = AVAudioPCMBuffer(pcmFormat: to, frameCapacity: frameCapacity) else {
            return nil
        }

        let inputBuffer = buffer
        var inputConsumed = false
        let status = converter.convert(to: output, error: nil, withInputFrom: { inNumPackets, _, outStatus in
            guard !inputConsumed else {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            inNumPackets.pointee = AVAudioPacketCount(inputBuffer.frameLength)
            return inputBuffer
        })
        guard status == .haveData, output.frameLength > 0, let source = output.int16ChannelData else {
            return nil
        }
        return Data(bytes: source, count: Int(output.frameLength) * 2)
    }

    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
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

    /// Half a second of soft 440 Hz sine at the upload rate, gently faded at the edges.
    static func makeTestTone() throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: pcmUploadSampleRate, channels: 1,
            interleaved: true)
        else {
            throw NSError(domain: "paseo.voice", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not build audio test tone"])
        }
        let frameCount = Int(pcmUploadSampleRate * 0.5)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else {
            throw NSError(domain: "paseo.voice", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not build audio test tone"])
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let channel = buffer.int16ChannelData else {
            throw NSError(domain: "paseo.voice", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not build audio test tone"])
        }
        for index in 0..<frameCount {
            let t = Double(index) / pcmUploadSampleRate
            let envelope = sin(Double.pi * Double(index) / Double(frameCount))
            let sample = sin(2 * Double.pi * 440 * t) * 0.3 * envelope
            channel[0][index] = Int16(max(-1, min(1, sample)) * 32767)
        }
        return buffer
    }
}

/// Once-only continuation resume for the test tone: the render completion and the 3 s
/// timeout race, and exactly one of them resumes the caller.
final class TestToneCompletion: @unchecked Sendable {
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
