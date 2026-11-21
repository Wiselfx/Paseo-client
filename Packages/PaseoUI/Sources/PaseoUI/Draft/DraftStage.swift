#if canImport(UIKit)
import SwiftUI

/// The draft's hero area: the greeting while nothing has been sent, then the pending bubble the
/// new conversation will carry (§3.2).
struct DraftStage: View {
    let pendingPrompt: String?
    /// Tapping the page outside the composer drops the keyboard (V5 §2).
    let onTapOutside: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The greeting fades out the moment the first prompt leaves, replaced by the pending bubble.
    var body: some View {
        ZStack {
            if let pendingPrompt {
                VStack(spacing: 0) {
                    ClaudeUserBubble(text: pendingPrompt, isPending: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                }
            } else {
                ClaudeHomeHero()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Simultaneous, so the workspace-line menu and the hero's own controls still take their taps.
        .simultaneousGesture(TapGesture().onEnded { onTapOutside() })
        .animation(Motion.disclosure.resolved(reduceMotion: reduceMotion), value: pendingPrompt)
    }
}
#endif
