#if canImport(UIKit)
import SwiftUI

/// The app's touch-feedback vocabulary, as SwiftUI sensory feedback. The same seven intents
/// `Haptics` has always offered, tuned the same: rare, soft and meaningful (Apple's own apps are
/// the bar). Views attach it with `.paseoFeedback(_:trigger:)`; `Haptics` remains only for code
/// that has no view to attach to (controllers, UIKit, the end of an async call).
enum PaseoFeedback: Equatable, Sendable {
    /// A value ticks: toggles, segments, pickers, a disclosure, a long-press menu.
    case selection
    /// A small confirmation: copy, a row action committed, an attachment added.
    case light
    /// Sending a message: a soft, full thump.
    case send
    /// Queueing a message (the long press firing).
    case medium
    /// A turn finished in the conversation on screen.
    case settle
    /// An action you waited on completed.
    case success
    /// A user-initiated action failed.
    case failure

    var sensory: SensoryFeedback {
        switch self {
        case .selection: .selection
        case .light: .impact(weight: .light, intensity: 0.6)
        case .send: .impact(flexibility: .soft, intensity: 0.9)
        case .medium: .impact(weight: .medium)
        case .settle: .impact(flexibility: .soft, intensity: 0.45)
        case .success: .impact(flexibility: .soft, intensity: 0.7)
        case .failure: .error
        }
    }
}
#endif
