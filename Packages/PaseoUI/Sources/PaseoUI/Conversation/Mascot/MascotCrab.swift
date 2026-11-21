#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The crab, feet on the composer card's top edge, flush with its right edge, above the card.
/// 104 × 72 pt of art; only the resting body takes touches.
///
/// **Reads:** `controller.mascotState`, `controller.showCostBubble`, `store.contextUsage` (only
/// while the bubble is open).
struct MascotCrab: View {
    @Bindable var controller: ChatController
    let store: ConversationStore?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PaseoSettingsKeys.mascot) private var mascotEnabled = true

    var body: some View {
        if mascotEnabled {
            ComposerCrab(state: controller.mascotState)
                // Long-press opens the cost bubble (M17); tap stays the poke.
                .onLongPressGesture(minimumDuration: 0.35) { controller.showCostBubble = true }
                .overlay(alignment: .topTrailing) {
                    if controller.showCostBubble, let usage = store?.contextUsage,
                        usage.totalCostUsd != nil || usage.inputTokens != nil
                            || usage.outputTokens != nil
                    {
                        Button(action: dismissCostBubble) { CostBubble(usage: usage) }
                            .buttonStyle(.plain)
                            .fixedSize()
                            .alignmentGuide(.top) { $0[.bottom] + 6 }
                            .transition(
                                .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing))
                            )
                            .accessibilityHint("Dismisses the cost")
                            .task {
                                try? await Task.sleep(for: .seconds(4))
                                controller.showCostBubble = false
                            }
                    }
                }
                .animation(
                    Motion.disclosure.resolved(reduceMotion: reduceMotion),
                    value: controller.showCostBubble
                )
                .offset(y: -72)
        }
    }

    private func dismissCostBubble() {
        controller.showCostBubble = false
    }
}
#endif
