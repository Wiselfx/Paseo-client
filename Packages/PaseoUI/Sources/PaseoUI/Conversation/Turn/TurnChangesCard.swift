#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - TurnChangesCard (G6 C11)

// NOTE: RemoteImagePipeline/G6: one row card at the end of a completed turn with file
// changes: "N files changed", the first files, the diff stat. It expands in place to
// the per-file list; each file opens its diff. Values only (R-2): the open verb comes
// from `RichActions`, and the card is `Equatable` so a streamed token re-evaluates
// only the tail turn's card.

/// The turn's file changes, as one row card. Streaming edits update only the tail
/// turn's instance: the summary rides on `Turn`, so unchanged turns compare equal.
struct TurnChangesCard: View, Equatable {
    let summary: TurnChangeSummary

    @Environment(\.richActions) private var richActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    /// Compared for `==`; interaction state is not part of identity (the TurnRow
    /// pattern: the row's inputs decide re-renders, not its disclosure).
    nonisolated static func == (lhs: TurnChangesCard, rhs: TurnChangesCard) -> Bool {
        lhs.summary == rhs.summary
    }

    private var fileCountLabel: String {
        "\(summary.fileCount) files changed"
    }

    private var metaText: String? {
        let names = summary.files.prefix(2).map(\.path)
        guard !names.isEmpty else { return nil }
        let rest = summary.fileCount - names.count
        if rest > 0 {
            return names.joined(separator: ", ") + " and \(rest) more"
        }
        return names.joined(separator: ", ")
    }

    var body: some View {
        PaseoCard(content:
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                        expanded.toggle()
                    }
                    Haptics.selection()
                } label: {
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
                if expanded {
                    VStack(alignment: .leading, spacing: 0) {
                        Divider().background(Palette.divider)
                        ForEach(summary.files, id: \.path) { file in
                            Button {
                                richActions?.openDiff(file.path)
                            } label: {
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
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open diff for \(file.path)")
                            .accessibilityHint(
                                "Shows what changed in this file")
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            })
            .animation(
                Motion.disclosure.resolved(reduceMotion: reduceMotion), value: expanded)
            .animation(
                Motion.disclosure.resolved(reduceMotion: reduceMotion), value: summary)
    }
}
#endif
