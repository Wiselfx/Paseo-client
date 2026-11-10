#if canImport(UIKit)
import AVFoundation
import Foundation
import PaseoStore

/// Attention sound cues (DSH `sound-cues`, D89): a short cue when an agent finishes (Tink) or
/// is blocked waiting on you (Pop), while the app is in the foreground and you are not looking
/// at that agent. Levels Off / Soft / Clear (DSH wording), default Off. No bundled audio: the
/// two voices are synthesized sine envelopes (Pop = three descending blips, Tink = a falling
/// tone with a harmonic), played through an `.ambient` session with `.mixWithOthers` — the
/// silent switch is respected and other audio is not interrupted. Two cues within 200 ms
/// coalesce into one, permission first (DSH `CUE_WINDOW_MS`).
public enum SoundCueLevel: String, Sendable, CaseIterable {
    case off
    case soft
    case clear

    public static let storageKey = "paseo.soundCues"

    public var title: String {
        switch self {
        case .off: "Off"
        case .soft: "Soft"
        case .clear: "Clear"
        }
    }

    /// The DSH gain table: soft 0.2, clear 0.55.
    public var gain: Float {
        switch self {
        case .off: 0
        case .soft: 0.2
        case .clear: 0.55
        }
    }

    public static func current(_ defaults: UserDefaults = .standard) -> SoundCueLevel {
        SoundCueLevel(rawValue: defaults.string(forKey: storageKey) ?? "") ?? .off
    }
}

/// Which cue a moment plays: Pop when an agent starts waiting, Tink when it finishes.
public enum SoundCueKind: Sendable, Equatable {
    case permission
    case completion
}

@MainActor
public final class SoundCuePlayer {
    public static let shared = SoundCuePlayer()

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var pending: SoundCueKind?
    private var flushTask: Task<Void, Never>?

    private init() {}

    /// Plays the cue for these intents, if any. Agent intents only (`finished` →
    /// completion, `permission` → permission); everything else is silent. The cue decision
    /// itself is `AttentionCenter`'s — this only sounds what it queued.
    public func playCues(for intents: [AttentionIntent]) {
        guard SoundCueLevel.current().gain > 0 else { return }
        var kind: SoundCueKind?
        for intent in intents {
            guard intent.target.kind == .agent else { continue }
            switch intent.reason {
            case "permission": kind = .permission
            case "finished": kind = kind == .permission ? .permission : .completion
            default: break
            }
        }
        guard let kind else { return }
        queue(kind)
    }

    /// Two cues inside 200 ms are one moment; permission takes it (DSH `queue`/`flush`).
    private func queue(_ kind: SoundCueKind) {
        if pending == .permission, kind == .completion { return }
        pending = kind
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
            guard let self else { return }
            self.flushTask = nil
            guard let kind = self.pending else { return }
            self.pending = nil
            self.play(kind)
        }
    }

    private func play(_ kind: SoundCueKind) {
        guard let (engine, node) = attachIfNeeded() else { return }
        node.volume = SoundCueLevel.current().gain * Self.headroom
        node.scheduleBuffer(Self.buffer(for: kind))
        if !engine.isRunning {
            try? engine.start()
        }
    }

    /// The engine + node, created once. The session is ambient (silent switch respected)
    /// and mixes with other audio (nothing is interrupted).
    private func attachIfNeeded() -> (AVAudioEngine, AVAudioPlayerNode)? {
        if let engine, let node { return (engine, node) }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: nil)
        self.engine = engine
        self.node = node
        return (engine, node)
    }

    // MARK: Voices (DSH synth.ts, at DSH's gain headroom)

    /// The two system files peak near a third of full scale; both voices sit under that.
    private static let headroom: Float = 0.55
    private static let sampleRate = 44_100.0

    private static func buffer(for kind: SoundCueKind) -> AVAudioPCMBuffer {
        switch kind {
        case .permission:
            // Pop: blips at 0/0.07/0.145 s from 560/500/470 Hz, weights 1/0.55/0.3.
            let voices: [(offset: Double, start: Double, peak: Double)] = [
                (0, 560, 0.5), (0.07, 500, 0.275), (0.145, 470, 0.15),
            ]
            return render(voices: voices.map { ($0.offset, $0.start, $0.start * 0.55, $0.peak) })
        case .completion:
            // Tink: 760→690 Hz over 55 ms plus a 1520 Hz harmonic.
            return render(voices: [(0, 760, 690, 0.72), (0, 1520, 1520, 0.1152)])
        }
    }

    /// One decaying sine per voice: exponential pitch ramp, exponential envelope. Mirrors
    /// DSH's `voice(start, end, attack, decay, peak)` with attack 2-4 ms.
    private static func render(
        voices: [(offset: Double, start: Double, end: Double, peak: Double)]
    ) -> AVAudioPCMBuffer {
        let synthesisRate = sampleRate
        let duration = (voices.map(\.offset).max() ?? 0) + 0.2
        let frameCount = AVAudioFrameCount(duration * synthesisRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: synthesisRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channels = buffer.floatChannelData!
        for voice in voices {
            let attack = 0.003 * synthesisRate
            let decay = 0.09 * synthesisRate
            let total = Int((attack + decay))
            let startFrame = Int(voice.offset * synthesisRate)
            var phase = 0.0
            for n in 0..<total {
                let at = Double(n)
                let start = voice.start
                let end = voice.end
                // Frequency ramps exponentially from start to end across attack+decay.
                let t = min(at / Double(total), 1)
                let freq = start * pow(end / start, t)
                phase += 2 * Double.pi * freq / synthesisRate
                let peak = voice.peak
                let envelope: Double
                if at < attack {
                    envelope = peak * (at / attack)
                } else {
                    envelope = peak * pow(0.0002 / max(peak, 0.0002), (at - attack) / decay)
                }
                let index = startFrame + n
                guard index < Int(frameCount) else { break }
                channels[0][index] += Float(sin(phase) * envelope)
            }
        }
        return buffer
    }
}
#endif
