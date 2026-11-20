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
                        row(index: index, item: item)
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

    private func row(index: Int, item: ChatOutlineItem) -> some View {
        let isCurrent = item.seq == activeSeq
        return Button {
            onJump(item.seq)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(PaseoFormat.integer(index + 1))
                    .font(.paseo(.codeSmall, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Palette.ink : Palette.secondaryInk)
                    .frame(width: 32, height: 32)
                    .background(isCurrent ? Palette.ink.opacity(0.10) : .clear, in: .circle)
                Text(item.preview)
                    .font(.paseo(.callout))
                    .foregroundStyle(isCurrent ? Palette.ink : Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("turnNav.\(index + 1)")
        .accessibilityLabel(isCurrent ? "Message \(index + 1), current" : "Jump to message \(index + 1)")
    }
}
#endif
