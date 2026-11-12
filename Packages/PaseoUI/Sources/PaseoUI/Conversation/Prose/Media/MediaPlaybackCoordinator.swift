#if canImport(UIKit)
import AVFoundation
import Foundation
import UIKit

// MARK: - MediaPlaybackCoordinator (G11 C3/C4)

// NOTE: RemoteImagePipeline/G11: one thing plays at a time. `activeID` is the single
// source of truth every inline player reads (R-1: one small value, never a store);
// starting one pauses the rest, and scrolling a player more than a screen away clears
// it, which tears the player down and stops the sound. This generalizes YouTube's
// old `InlineYouTubePlayback` (same shape, now shared by video and audio).

/// Which inline player may make noise right now, if any.
@MainActor @Observable
final class MediaPlaybackCoordinator {
    static let shared = MediaPlaybackCoordinator()

    private(set) var activeID: String?
    /// The last reported playback position per player, so a scrolled-away player
    /// resumes where it left off instead of restarting.
    private var positions: [String: Double] = [:]

    func remember(position: Double, for id: String) {
        positions[id] = max(0, position)
    }

    func position(for id: String) -> Double? {
        positions[id]
    }

    /// Starts `id`, stopping whatever played before. Cards tear their own players
    /// down when they lose the id (see their `onChange`).
    func play(_ id: String) {
        activeID = id
    }

    /// Stops `id`, but only if it is still the active one: a newer player wins races.
    func stop(_ id: String) {
        if activeID == id {
            activeID = nil
        }
    }
}

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
