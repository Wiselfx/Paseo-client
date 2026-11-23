#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The full-screen dock's terminal switcher: the current terminal's dot and name as a glass
/// capsule that opens a menu of the others.
struct TerminalSwitcherMenu: View {
    let terminals: [TerminalInfo]
    let current: TerminalInfo
    let dotState: StatusDot.State
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(terminals) { terminal in
                Button(
                    terminal.displayName,
                    systemImage: terminal.id == current.id ? "checkmark" : "terminal"
                ) {
                    select(terminal.id)
                }
            }
        } label: {
            HStack(spacing: Space.sm) {
                StatusDot(dotState)
                Text(current.displayName)
                    .font(.paseo(.footnote))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Space.md)
            .frame(maxWidth: TerminalChrome.switcherMaxWidth, minHeight: TerminalChrome.hit)
            .contentShape(.capsule)
        }
        .terminalGlass(.capsule, interactive: true)
        .accessibilityLabel("Terminal \(current.displayName)")
        .accessibilityHint("Switches terminal")
    }

    private func select(_ id: String) {
        guard id != current.id else { return }
        Haptics.selection()
        onSelect(id)
    }
}
#endif
