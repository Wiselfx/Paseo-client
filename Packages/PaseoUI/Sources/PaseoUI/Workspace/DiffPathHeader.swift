#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The diff page's header: the file path (and its old path after a rename) with the +/- stat.
struct DiffPathHeader: View {
    let file: ParsedDiffFile

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(file.path)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                if let oldPath = file.oldPath {
                    Text("renamed from \(oldPath)")
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: Space.sm)
            DiffStat(added: file.additions, removed: file.deletions)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, 10)
    }
}
#endif
