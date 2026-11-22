#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// A review draft comment, drawn as a quiet card under its anchor line, with edit and delete.
struct DiffDraftCard: View {
    let draft: WorkspaceReviewDraftComment
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: "text.bubble")
                .font(.glyph(.small, weight: .regular))
                .foregroundStyle(Palette.tertiaryInk)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(lineRangeLabel)
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.tertiaryInk)
                    Text("Review comment")
                        .font(.paseo(.caption, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                    Spacer(minLength: 4)
                    iconButton("pencil", label: "Edit review comment", action: onEdit)
                    iconButton("trash", label: "Delete review comment", action: onDelete)
                }
                Button(action: onEdit) {
                    Text(draft.body)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Review comment: \(draft.body)")
                .accessibilityHint("Edits the comment")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Palette.quoteWash, in: .rect(cornerRadius: Radius.md))
        .padding(.leading, 46)
        .padding(.trailing, Space.md)
        .padding(.vertical, 3)
    }

    private var lineRangeLabel: String {
        draft.startLine == draft.endLine ? "L\(draft.startLine)" : "L\(draft.startLine)–\(draft.endLine)"
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 30, height: 30)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
#endif
