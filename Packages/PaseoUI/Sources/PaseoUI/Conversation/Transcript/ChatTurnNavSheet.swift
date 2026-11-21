#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// U5: "Jump to message" — the chat outline's prompts, every one of them.
///
/// The list is the daemon's index for the whole conversation (UX spec §4.3), so opening the sheet
/// never pages history in: choosing an unloaded prompt fetches just its window.
struct ChatTurnNavSheet: View {
    let store: ConversationStore
    let items: [ChatOutlineItem]
    let activeSeq: Int?
    let onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Jump to message", close: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items.enumerated(), id: \.element.id) { index, item in
                        ChatTurnNavRow(
                            number: index + 1, item: item, isCurrent: item.seq == activeSeq
                        ) { select(item) }
                        if item.id != items.last?.id {
                            ClaudeDivider().padding(.leading, 56)
                        }
                    }
                    if store.promptOutline.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .accessibilityLabel("Loading earlier messages")
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Palette.background)
        }
        .presentationDetents([.medium, .large])
        .task { store.promptOutline.refresh(timelineEpoch: store.timeline.epoch) }
    }

    private func select(_ item: ChatOutlineItem) {
        onJump(item.seq)
        dismiss()
    }
}
#endif
