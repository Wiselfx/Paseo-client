#if canImport(UIKit)
import SwiftUI

/// The icon-only "new terminal" glass circle; shows a spinner while the daemon creates the
/// terminal and says so as its accessibility value.
struct TerminalNewButton: View {
    let isCreating: Bool
    let action: () -> Void

    private var busyValue: LocalizedStringKey { isCreating ? "Creating" : "" }

    var body: some View {
        Button(action: action) {
            Group {
                if isCreating {
                    ProgressView().controlSize(.mini).tint(Palette.secondaryInk)
                } else {
                    Label("New terminal", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .font(.glyph(.small, weight: .medium))
                }
            }
            .frame(width: TerminalChrome.hit, height: TerminalChrome.hit)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.ink)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(isCreating)
        .accessibilityLabel("New terminal")
        .accessibilityValue(busyValue)
        .accessibilityIdentifier("terminal.new")
    }
}
#endif
