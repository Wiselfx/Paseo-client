#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One terminal's tab in the chip bar: a status dot and the name, with rename and close in the
/// context menu. The dot only says "something happened" through colour and a pulse, so the
/// chip also speaks the state as its accessibility value. The selected chip carries a glass
/// capsule that morphs between chips (`glassEffectID`) inside the bar's glass container.
struct TerminalChip: View {
    let terminal: TerminalInfo
    let isSelected: Bool
    let dotState: StatusDot.State
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onRename: () -> Void
    let onClose: () -> Void

    private var statusText: LocalizedStringKey {
        switch dotState {
        case .attention: "Needs input"
        case .running: "Running"
        case .unread: "New output"
        case .failed: "Failed"
        case .idle: "Idle"
        }
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: Space.sm) {
                StatusDot(dotState)
                Text(terminal.displayName)
                    .font(.paseo(.footnote, weight: isSelected ? .medium : nil))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.md)
            .frame(minHeight: TerminalChrome.chipVisualHeight)
            .background {
                if isSelected {
                    Color.clear
                        .terminalGlass(.capsule)
                        .glassEffectID("selection", in: namespace)
                }
            }
            .padding(.vertical, (TerminalChrome.hit - TerminalChrome.chipVisualHeight) / 2)
            .contentShape(.rect)
        }
        .buttonStyle(TerminalChipPressStyle())
        .accessibilityLabel("Terminal \(terminal.displayName)")
        .accessibilityValue(statusText)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: "Rename", onRename)
        .accessibilityAction(named: "Close", onClose)
        .contextMenu {
            Button("Rename…", systemImage: "pencil", action: onRename)
            Button("Close", systemImage: "xmark", role: .destructive, action: onClose)
        }
    }

    private func select() {
        guard !isSelected else { return }
        Haptics.selection()
        onSelect()
    }
}
#endif
