#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// M7i — the turn navigator: a slim numbered rail of your messages at the transcript's trailing
/// edge. It shows while scrolling (and on demand via the edge strip), never for short chats,
/// and jumps to a turn on tap. Current turn highlighted. Reduce Motion respected.
struct ClaudeTurnRail: View {
    let turns: [Turn]
    let currentTurnId: String?
    let onJump: (String) -> Void

    private let typography = ClaudeTypography()

    /// Only chats with at least this many user messages show the rail.
    static let minimumTurns = 4

    /// Width the transcript's trailing padding reserves so no message text ever sits under the
    /// rail (UX spec §4.3). 26 pt mark + 3 pt padding each side + the 4 pt inset from the edge.
    static let reservedWidth: CGFloat = 36

    /// The rail's rows: the user message of each turn, in order.
    var railTurns: [Turn] {
        turns.filter { $0.userMessage != nil }
    }

    var body: some View {
        if railTurns.count >= Self.minimumTurns {
            VStack(alignment: .center, spacing: 2) {
                ScrollView(.vertical) {
                    VStack(spacing: 6) {
                        ForEach(Array(railTurns.enumerated()), id: \.element.id) { index, turn in
                            railMark(index: index, turn: turn)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 340)
            }
            .padding(3)
            // A thin, translucent strip: the transcript stays readable under it.
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
            .accessibilityIdentifier("transcript.turnRail")
        }
    }

    private func railMark(index: Int, turn: Turn) -> some View {
        let isCurrent = currentTurnId == turn.id
        return Button {
            Haptics.selection()
            onJump(turn.id)
        } label: {
            Text("\(index + 1)")
                .font(typography.mono(10, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? ClaudePalette.ink : ClaudePalette.secondaryInk)
                .frame(width: 26, height: 26)
                .background(isCurrent ? ClaudePalette.ink.opacity(0.10) : .clear, in: .circle)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCurrent ? "Message \(index + 1), current" : "Jump to message \(index + 1)")
    }
}

/// M7i: the on-demand list of your messages behind the header's "Jump to message…" — same rows as
/// the rail, full text, current highlighted. Tap jumps and dismisses.
///
/// The sheet owns "every prompt of the conversation", not just the loaded pages: opening it pages
/// the rest of the history in (UX spec §4.3), rows appear as they arrive, and a spinner row sits
/// at the end while `hasOlder` is still true.
struct ChatTurnNavSheet: View {
    let store: ConversationStore
    let currentTurnId: String?
    let onJump: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    private let typography = ClaudeTypography()

    /// Only turns with a user message, in order.
    var rows: [Turn] { store.turns.filter { $0.userMessage != nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, turn in
                        row(index: index, turn: turn)
                        if turn.id != rows.last?.id {
                            ClaudeDivider().padding(.leading, 56)
                        }
                    }
                    if store.timeline.hasOlder {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .accessibilityLabel("Loading earlier messages")
                    }
                }
                .padding(.vertical, 4)
            }
            .background(ClaudePalette.background)
            .navigationTitle("Jump to message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .presentationDetents([.medium])
            .task { await store.loadAllOlder() }
        }
    }

    private func row(index: Int, turn: Turn) -> some View {
        let isCurrent = currentTurnId == turn.id
        return Button {
            Haptics.selection()
            onJump(turn.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(typography.mono(12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? ClaudePalette.ink : ClaudePalette.secondaryInk)
                    .frame(width: 32, height: 32)
                    .background(isCurrent ? ClaudePalette.ink.opacity(0.10) : .clear, in: .circle)
                Text(userText(turn))
                    .font(typography.sans(14))
                    .foregroundStyle(isCurrent ? ClaudePalette.ink : ClaudePalette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ClaudePalette.ink)
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

    private func userText(_ turn: Turn) -> String {
        guard let row = turn.userMessage, case .userMessage(let message) = row.item else { return "" }
        return message.text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
