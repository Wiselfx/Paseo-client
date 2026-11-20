#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// U5: the prompt rail, over the transcript's trailing edge while scrolling. Its own body, so a
/// streamed token never re-evaluates it.
struct TranscriptRail: View {
    let store: ConversationStore
    let controller: ChatController
    let engine: TranscriptEngine
    @Environment(\.shellDrawer) private var shellDrawer

    var body: some View {
        ZStack {
            if ChatOutlineRail.promptRailEnabled, case .ready = store.phase, controller.outlineAvailable {
                GeometryReader { proxy in
                    ChatOutlineRail(
                        items: controller.outlineItems,
                        activeSeq: store.promptOutline.activeSeq,
                        viewportHeight: proxy.size.height,
                        isRevealed: engine.ui.turnNavVisible,
                        onJump: { seq in controller.jumpToPrompt(seq) },
                        onReveal: { engine.revealTurnRail() })
                }
                .transition(.opacity)
            }
        }
        // While the rail is up its edge belongs to it, not to the drawer's edge pan.
        .onChange(of: engine.ui.turnNavVisible, initial: true) { _, shown in
            shellDrawer?.trailingEdgeReserved = shown
        }
        .onDisappear { shellDrawer?.trailingEdgeReserved = false }
    }
}
#endif
