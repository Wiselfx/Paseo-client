#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The chips along the top of the terminal page: one per terminal, then "New". Each chip's
/// status dot comes in as a value, so the bar does not depend on the page's `lastViewed` state.
struct TerminalChipBar: View {
    let terminals: [TerminalInfo]
    let selectedId: String?
    let dotStates: [String: StatusDot.State]
    let isCreating: Bool
    let onSelect: (String) -> Void
    let onRename: (TerminalInfo) -> Void
    let onClose: (TerminalInfo) -> Void
    let onCreate: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.sm) {
                ForEach(terminals) { terminal in
                    TerminalChip(
                        terminal: terminal,
                        isSelected: terminal.id == selectedId,
                        dotState: dotStates[terminal.id] ?? .idle,
                        onSelect: { onSelect(terminal.id) },
                        onRename: { onRename(terminal) },
                        onClose: { onClose(terminal) })
                }
                TerminalNewButton(isCreating: isCreating, action: onCreate)
            }
            .padding(.horizontal, Space.lg)
            // A horizontal scroll view is as tall as its content, so the bar follows the chips
            // (44 pt minimum, taller under larger text) instead of clipping them.
            .padding(.vertical, Space.xs)
        }
        .scrollIndicators(.hidden)
    }
}
#endif
