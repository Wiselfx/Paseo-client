import PaseoStore
import SwiftUI

@testable import PaseoUI

/// The transcript framed the way `ChatScreen` frames it: SwiftUI bars inset at the top and bottom
/// (clear stand-ins with the bars' heights), so the cells see the same safe area as in the app.
struct HarnessChatScreen: View {
    let store: ConversationStore
    let controller: ChatController
    let topBar: CGFloat
    let bottomBar: CGFloat

    var body: some View {
        TranscriptView(store: store, controller: controller)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topBar)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bottomBar)
            }
    }
}
