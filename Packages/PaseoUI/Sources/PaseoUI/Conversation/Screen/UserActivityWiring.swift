#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import UIKit

/// Toast notices and the turn-finished haptic: neither is drawn by this screen.
struct UserActivityWiring: ViewModifier {
    let store: ConversationStore
    let controller: ChatController
    @Binding var focused: Bool

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: store.lastNotice?.message) { _, message in
                guard let message else { return }
                controller.showToast(message)
                store.clearNotice()
            }
            .paseoFeedback(.settle, trigger: store.isRunning) { wasRunning, isRunning in
                wasRunning && !isRunning
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    controller.feedMascot(.userActivity(at: .now))
                    controller.requestEndScroll()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                controller.dictation.stop(keepingDraft: true)
                // M15: voice mode stops cleanly in the background (mic + wake lock off).
                controller.voiceEngineIfCreated?.stopCapture()
                if controller.session.voiceSession.isVoiceMode {
                    Task { await controller.session.voiceSession.stop() }
                }
            }
    }
}
#endif
