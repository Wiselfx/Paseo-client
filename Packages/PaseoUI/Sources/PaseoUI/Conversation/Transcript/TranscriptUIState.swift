#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The little state SwiftUI draws from the engine: the landing line and the rail.
@MainActor @Observable
final class TranscriptUIState {
    var landingTurnId: String?
    var turnNavVisible = false
    /// The screen's environment that UIKit does not carry into the cells' hosting views: a covered
    /// chat or a backgrounded app stops every running loop in the transcript.
    var surfaceObscured = false
    var scenePhase: ScenePhase = .active
}
#endif
