#if canImport(UIKit)
import AVFoundation
import Foundation
import OSLog
import PaseoStore

/// One-shot buffer conversion with a converter cached per input format. Not thread-safe:
/// each instance is confined to one queue or actor.
final class VoiceFormatConverter {
    private var converters: [String: AVAudioConverter] = [:]

    /// Converts `input` into `outputFormat`. The input block hands the buffer over once
    /// and then reports end of stream, so `convert` can only return `.haveData`,
    /// `.inputRanDry` (output not full yet) or `.endOfStream` — all of them mean the
    /// output holds usable samples.
    /// `reset` is for one-shot converters (independent playback chunks). A continuous capture
    /// stream must keep the sample-rate converter's phase across buffers; resetting it per
    /// buffer throws that away and drops a fraction of a sample each time.
    func convert(
        _ input: AVAudioPCMBuffer, to outputFormat: AVAudioFormat, reset: Bool = true
    ) -> AVAudioPCMBuffer? {
        let key = Self.key(input.format)
        let converter: AVAudioConverter
        if let cached = converters[key] {
            if reset { cached.reset() }
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
#endif
