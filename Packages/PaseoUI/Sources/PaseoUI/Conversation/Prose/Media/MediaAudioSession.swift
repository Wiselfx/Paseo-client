#if canImport(UIKit)
import AVFoundation
import Foundation
import UIKit

// MARK: - MediaAudioSession (G11 C4)

// NOTE: RemoteImagePipeline/G11: the audio session is configured off main (the known
// `setActive` hang-risk), and coordinated with voice/dictation's `MicrophoneSessionOwner`
// so playback never steals or breaks the mic session: while voice capture owns the
// session we play without touching it, and we only deactivate what we activated.

/// `.playback` activation for media cards, kept off the main thread and out of the
/// voice session's way.
@MainActor
enum MediaAudioSession {
    private static var configuredForPlayback = false

    /// Activates `.playback` unless realtime voice owns the session (in which case
    /// playback rides along without touching it). Off main; one no-op per state.
    static func activateForPlayback() async {
        guard !MicrophoneSessionOwner.voiceCaptureActive, !configuredForPlayback else { return }
        configuredForPlayback = await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
                return true
            } catch {
                return false
            }
        }.value
    }

    /// Undoes our own activation, and only that: never when voice capture is live.
    /// The category goes back to `.ambient` with it, so later UI sounds respect
    /// the silent switch again (H1 restores the same after voice sessions).
    static func deactivateAfterPlayback() async {
        guard configuredForPlayback, !MicrophoneSessionOwner.voiceCaptureActive else { return }
        let deactivated = await Task.detached(priority: .userInitiated) {
            do {
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
                try AVAudioSession.sharedInstance().setActive(
                    false, options: .notifyOthersOnDeactivation)
                return true
            } catch {
                return false
            }
        }.value
        if deactivated {
            configuredForPlayback = false
        }
    }
}
#endif
