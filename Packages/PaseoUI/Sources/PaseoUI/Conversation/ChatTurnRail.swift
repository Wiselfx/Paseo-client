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
            .background(ClaudePalette.adaptive(light: 0.98, dark: 0.12), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(ClaudePalette.cardBorder, lineWidth: 0.5)
            }
            .accessibilityIdentifier("transcript.turnRail")
        }
    }

    private func railMark(index: Int, turn: Turn) -> some View {
        let isCurrent = currentTurnId == turn.id
        return Button {
            Haptics.selection()
            onJump(turn.id)
        } label: {
            Text("\(PaseoFormat.integer(index + 1))")
                .font(typography.mono(10, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? ClaudePalette.ink : ClaudePalette.secondaryInk)
                .frame(width: 26, height: 26)
                .background(isCurrent ? ClaudePalette.chip : .clear, in: .circle)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCurrent ? "Message \(index + 1), current" : "Jump to message \(index + 1)")
    }
}

/// M7i: the on-demand list of your messages behind the header's "Jump to message…" — same rows as
/// the rail, full text, current highlighted. Tap jumps and dismisses.
struct ChatTurnNavSheet: View {
    let turns: [Turn]
    let currentTurnId: String?
    let onJump: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    private let typography = ClaudeTypography()

    /// Only turns with a user message, in order.
    var rows: [Turn] { turns.filter { $0.userMessage != nil } }

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
                Text("\(PaseoFormat.integer(index + 1))")
                    .font(typography.mono(12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? ClaudePalette.ink : ClaudePalette.secondaryInk)
                    .frame(width: 32, height: 32)
                    .background(isCurrent ? ClaudePalette.chip : .clear, in: .circle)
                Text(userText(turn))
                    .font(typography.sans(14))
                    .foregroundStyle(isCurrent ? ClaudePalette.ink : ClaudePalette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if isCurrent {
                    Circle().fill(ClaudePalette.ink).frame(width: 6, height: 6)
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
