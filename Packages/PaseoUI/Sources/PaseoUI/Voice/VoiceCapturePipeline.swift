#if canImport(UIKit)
import AVFoundation
import Foundation
import OSLog
import PaseoStore

/// Capture DSP that must not run on the main actor: copies each tap buffer, computes the
/// level, and converts to the 16 kHz int16 mono PCM the daemon expects. One serial queue,
/// one cached converter per input format.
final class VoiceCapturePipeline: @unchecked Sendable {
    static let uploadSampleRate = 16_000.0
    /// Upstream's `discardFirstInputMillis` (`expo-two-way-audio/ios/AudioEngine.swift:30`):
    /// the mic's first two seconds after the first playback chunk are dropped, level included,
    /// because AEC has not adapted yet and the mic would otherwise hear the reply.
    static let warmupDiscardSeconds = 2.0

    private let queue = DispatchQueue(label: "paseo.voice.capture", qos: .userInitiated)
    private let onChunk: @Sendable (Double, Data) -> Void
    private let converter = VoiceFormatConverter()
    private let meter: AudioLevelMeter
    private let coalescer = VoiceUploadCoalescer()
    private let uploadFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: VoiceCapturePipeline.uploadSampleRate,
        channels: 1, interleaved: true)

    // Queue-confined delivery state. The engine's tap size is a hint, so a device may hand us
    // 1024-frame buffers (≈ 47 per second): coalesce them to one delivery per 33 ms instead of
    // hopping to the main actor per buffer.
    private var frameCount = 0
    private var lastLevelLog: TimeInterval = 0
    /// AEC warm-up: samples arriving before this instant are dropped, and the window is armed
    /// at most once per capture session (`resetWarmupWindow` clears both on each start).
    private var discardUntil: TimeInterval = 0
    private var discardArmed = false

    /// `onChunk` receives the eased level and the PCM from the capture queue, in capture order.
    init(meter: AudioLevelMeter, onChunk: @escaping @Sendable (Double, Data) -> Void) {
        self.meter = meter
        self.onChunk = onChunk
    }

    /// A new capture session starts a fresh warm-up window (E1b): clears the previous one, so a
    /// deadline armed before capture stopped cannot drop the new session's first audio.
    func resetWarmupWindow() {
        queue.async { [weak self] in
            guard let self else { return }
            self.discardArmed = false
            self.discardUntil = 0
            self.coalescer.reset()
            self.frameCount = 0
            self.lastLevelLog = 0
        }
    }

    /// Arms the AEC warm-up window: mic input is dropped until `deadline` (E1b). Called from
    /// the main actor, applied on the capture queue before the next delivery. Only the first
    /// call per session counts.
    func discardInput(until deadline: TimeInterval) {
        queue.async { [weak self] in
            guard let self, !self.discardArmed else { return }
            self.discardArmed = true
            self.discardUntil = deadline
            // Anything already accumulated is inside the window too.
            self.coalescer.reset()
        }
    }

    /// Called on the audio thread. The engine reuses `buffer` as soon as this returns, so
    /// the samples are copied here; everything else runs on the serial queue.
    func capture(_ buffer: AVAudioPCMBuffer) {
        guard let frame = Frame(buffer) else { return }
        queue.async { [weak self] in
            guard let self, let result = self.process(frame) else { return }
            self.accumulate(result)
        }
    }

    /// Maps the level into the ring every buffer, and hands the PCM to the main actor at most 30
    /// times a second. Outside the AEC warm-up window nothing is dropped.
    private func accumulate(_ result: (level: Double, pcm: Data)) {
        let now = Date.now.timeIntervalSince1970
        // The AEC warm-up window (E1b): upstream skips the whole tap body, so neither the level
        // nor the PCM leaves the device. One timestamp compare per buffer, no timer.
        if discardUntil > 0 {
            guard now >= discardUntil else { return }
            discardUntil = 0
            VoiceLog.log.info("capture: AEC warm-up window ended")
        }
        // The bars read this ring from their own display link: the level never hops to the main
        // actor per buffer, and no SwiftUI view is invalidated by one (H1 §3).
        let eased = Double(meter.push(rms: Float(result.level), at: now))
        logLevel(rms: result.level, eased: eased, at: now)
        guard let pcm = coalescer.append(result.pcm, at: now) else { return }
        frameCount += 1
        if frameCount == 1 {
            VoiceLog.log.info("capture: first frame sent (\(pcm.count) bytes)")
        } else if frameCount % 50 == 0 {
            VoiceLog.log.debug("capture: \(self.frameCount) frames sent")
        }
        onChunk(eased, pcm)
    }

    /// Once a second, at debug: the raw RMS in dB and the eased 0…1 level. This is the line the
    /// next device run is read from when the bars still look wrong.
    private func logLevel(rms: Double, eased: Double, at now: TimeInterval) {
        guard now - lastLevelLog >= 1 else { return }
        lastLevelLog = now
        let db = 20 * log10(max(rms, 1e-5))
        VoiceLog.log.debug(
            "level db=\(db.formatted(.number.precision(.fractionLength(1))), privacy: .public) eased=\(eased.formatted(.number.precision(.fractionLength(3))), privacy: .public)")
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
        guard let converted = converter.convert(source, to: upload, reset: false),
            // `int16ChannelData` is an array of channel pointers; the samples live behind the
            // first one. Copying from the pointer itself sent the array's own bytes (heap
            // addresses) to the daemon as "speech" (H1 root cause).
            let pcm = converted.int16ChannelData?[0]
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
#endif
