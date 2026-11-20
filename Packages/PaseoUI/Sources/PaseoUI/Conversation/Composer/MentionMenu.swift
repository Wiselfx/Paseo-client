#if canImport(UIKit)
import SwiftUI
import PaseoStore

/// The @-mention popover. Same chrome as the slash menu. Tap a row: files insert, folders drill in.
struct MentionMenu: View {
    let rows: [MentionIndexRow]
    let isBuilding: Bool
    let onPick: (MentionIndexRow) -> Void

    var body: some View {
        ComposerMenuContainer(accessibilityIdentifier: "composer.mentionMenu") {
            if isBuilding, rows.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading files…")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            mentionRow(row)
                        }
                    }
                }
                .frame(maxHeight: 248)
                .scrollIndicators(.hidden)
            }
        }
    }

    private func mentionRow(_ row: MentionIndexRow) -> some View {
        Button {
            onPick(row)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: row.isDirectory ? "folder" : "doc")
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 20)
                Text("@\(row.path.trimmingSuffix(while: { $0 == "/" }))")
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if row.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.glyph(.small, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.isDirectory ? "Folder \(row.path)" : "File \(row.path)")
        .accessibilityAddTraits(row.isDirectory ? [] : .isButton)
    }
}
extension String {
    func trimmingSuffix(while predicate: (Character) -> Bool) -> String {
        var end = endIndex
        while end > startIndex, predicate(self[index(before: end)]) {
            end = index(before: end)
        }
        return String(self[..<end])
    }
}
#endif
