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
#endif
