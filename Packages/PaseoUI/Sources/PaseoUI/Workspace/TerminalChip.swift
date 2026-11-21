#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One terminal's tab in the chip bar: a status dot and the name, with rename and close in the
/// context menu. The dot only says "something happened" through colour and a pulse, so the
/// chip also speaks the state as its accessibility value.
struct TerminalChip: View {
    let terminal: TerminalInfo
    let isSelected: Bool
    let dotState: StatusDot.State
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
        Button {
            guard !isSelected else { return }
            Haptics.selection()
            onSelect()
        } label: {
            HStack(spacing: 6) {
                StatusDot(dotState)
                Text(terminal.displayName)
                    .font(.paseo(.footnote))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.md)
            .frame(minHeight: 44)
            .background(isSelected ? Palette.chip : Color.clear, in: .capsule)
            .overlay {
                Capsule().strokeBorder(
                    Palette.cardBorder, lineWidth: isSelected ? 0 : 0.5)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Terminal \(terminal.displayName)")
        .accessibilityValue(statusText)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .contextMenu {
            Button("Rename…", systemImage: "pencil", action: onRename)
            Button("Close", systemImage: "xmark", role: .destructive, action: onClose)
        }
    }
}
#endif
