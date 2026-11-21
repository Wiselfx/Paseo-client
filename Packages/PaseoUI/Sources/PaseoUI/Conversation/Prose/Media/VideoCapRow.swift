#if canImport(UIKit)
import SwiftUI

/// The 64 MB cap row (G10 C10 pattern): no download, Share and Show in Files only.
struct VideoCapRow: View {
    let fileName: String
    /// The daemon path, when there is one: enables Show in Files.
    let filePath: String?

    @Environment(\.richActions) private var richActions

    var body: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            Image(systemName: "film")
                .font(.glyph(.large, weight: .light))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Too large to preview")
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(fileName)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Space.sm)
            if let filePath {
                Button("Files") {
                    richActions?.openFile(filePath)
                }
                .buttonStyle(.plain)
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(minWidth: Metrics.hitSize, minHeight: Metrics.hitSize)
                .accessibilityLabel("Show in Files")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, minHeight: Metrics.rowCardMinHeight - Space.md * 2, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Video too large to preview, \(fileName)")
    }
}
#endif
