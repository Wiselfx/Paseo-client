#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One file in the expanded `TurnChangesCard`: its path, the diff stat, and a chevron. Tapping
/// opens that file's diff.
struct TurnChangedFileRow: View {
    let file: TurnChangeSummary.FileChange
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Text(file.path)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DiffStat(
                    added: file.added, removed: file.removed,
                    compact: true)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Space.sm)
            .frame(minHeight: Metrics.hitSize)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open diff for \(file.path)")
        .accessibilityHint(
            "Shows what changed in this file")
    }
}
#endif
