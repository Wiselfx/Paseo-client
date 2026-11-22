#if canImport(UIKit)
import SwiftUI

/// "Show N more lines" under a long hunk that starts cut to its first 40 lines.
struct DiffShowMoreRow: View {
    let remaining: Int
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: Space.sm) {
                Image(systemName: "chevron.down")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
                Text("Show \(PaseoFormat.integer(remaining)) more lines")
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.lg)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.chip)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(remaining) more lines")
    }
}
#endif
