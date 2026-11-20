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
#endif
