import PaseoStore
import PaseoUI
import SwiftUI

/// Drains queued attention intents into the notification coordinator, in its own body: the shell
/// and the root never observe the attention queue (R5 §4.6).
struct AttentionDelivery: ViewModifier {
    let session: HostSession
    let scenePhase: ScenePhase
    let notifications: NotificationCoordinator

    func body(content: Content) -> some View {
        content
            .onAppear { deliver() }
            .onChange(of: session.attention.pending) { _, _ in deliver() }
            .onChange(of: scenePhase) { _, _ in deliver() }
    }

    /// Drains queued attention intents and hands them to the notification coordinator. Runs on
    /// every change, on appear, and when the app returns to the foreground.
    private func deliver() {
        let intents = session.attention.drain()
        guard !intents.isEmpty else { return }
        // Sound cues (M12): foreground only, and AttentionCenter already dropped the agent
        // the user is looking at.
        if scenePhase == .active {
            SoundCuePlayer.shared.playCues(for: intents)
        }
        Task { await notifications.deliver(intents) }
    }
}
