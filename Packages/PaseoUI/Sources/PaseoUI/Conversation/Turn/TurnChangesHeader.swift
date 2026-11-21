#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The disclosure row of `TurnChangesCard`: "N files changed", the first files, the diff stat and
/// a chevron. The card owns `expanded`; this row only draws it and reports the tap.
struct TurnChangesHeader: View {
    let summary: TurnChangeSummary
    let expanded: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// "1 file changed" / "2 files changed": inflected by the system, kept a plain `String`
    /// because the accessibility label interpolates it.
    private var fileCountLabel: String {
        String(
            AttributedString(
                localized: "^[\(summary.fileCount) file](inflect: true) changed", bundle: #bundle
            ).characters)
    }

    private var metaText: String? {
        let names = summary.files.prefix(2).map(\.path)
        guard !names.isEmpty else { return nil }
        let rest = summary.fileCount - names.count
        if rest > 0 {
            return (names + [String(localized: "\(rest) more")]).formatted()
        }
        return names.formatted()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: "doc.badge.ellipsis")
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileCountLabel)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.ink)
                    if let metaText {
                        Text(metaText)
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                DiffStat(added: summary.added, removed: summary.removed, compact: true)
                Image(systemName: "chevron.down")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Metrics.rowCardMinHeight - Space.md * 2)
            .contentShape(.rect)
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("\(fileCountLabel). \(metaText ?? "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(expanded ? "Collapses the file list" : "Expands the file list")
    }
}
#endif
