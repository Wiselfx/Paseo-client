#if canImport(UIKit)
import AVFoundation
import PaseoStore
import Speech
import SwiftUI

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
