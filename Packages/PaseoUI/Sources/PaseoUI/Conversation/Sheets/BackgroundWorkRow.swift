#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// M7g: a quiet row near the transcript end while the daemon reports background work,
/// tapping through to the sheet (kind, command/label, started, Stop with confirmation
/// for shells) when the stop gate is on.

struct BackgroundWorkRow: View {
    let items: [BackgroundWorkItem]
    let action: () -> Void

    /// "2 background tasks" / "1 background task".
    private var text: String {
        items.count == 1 ? "1 background task" : "\(items.count) background tasks"
    }

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                WorkIcon(kind: .shell)
                Text(text)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(Palette.adaptive(light: 0.96, dark: 0.10), in: .rect(cornerRadius: Radius.sm))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transcript.backgroundWork")
        .accessibilityLabel(text)
    }
}
#endif
