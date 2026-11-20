#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Carries the screen's environment that UIKit does not hand to the cells (a drawer covering the
/// chat, the app's scene phase) into the engine's state, from a body of its own: a flip never
/// re-evaluates the transcript.
struct TranscriptEnvironmentRelay: View {
    let ui: TranscriptUIState
    @Environment(\.isSurfaceObscured) private var isSurfaceObscured
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .onChange(of: isSurfaceObscured, initial: true) { _, value in
                if ui.surfaceObscured != value { ui.surfaceObscured = value }
            }
            .onChange(of: scenePhase, initial: true) { _, value in
                if ui.scenePhase != value { ui.scenePhase = value }
            }
    }
}
#endif
