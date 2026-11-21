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

    /// "2 background tasks" / "1 background task", inflected by the system.
    private var label: Text {
        Text("^[\(items.count) background task](inflect: true)")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                WorkIcon(kind: .shell)
                label
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, Space.md)
            .frame(minHeight: 36)
            .background(Palette.adaptive(light: 0.96, dark: 0.10), in: .rect(cornerRadius: Radius.sm))
            // 36 + 8 = 44 pt hit area, as SubagentTrackPill does.
            .padding(.vertical, Space.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transcript.backgroundWork")
        .accessibilityLabel(label)
    }
}
#endif
