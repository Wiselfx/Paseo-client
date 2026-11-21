#if canImport(UIKit)
import SwiftUI
import UIKit

/// The row inside a file card: the PDF's first page or a type glyph, the name and its meta line,
/// and a spinner while the download runs or a chevron otherwise. The box is the same height
/// throughout; only the thumbnail fades in.
struct RichFileRow: View {
    let fileName: String
    let meta: String?
    let glyph: String
    let thumbnail: UIImage?
    let downloading: Bool

    var body: some View {
        HStack(spacing: Space.sm) {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: Radius.sm, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: glyph)
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: Metrics.hitSize - Space.md, alignment: .center)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let meta {
                    Text(meta)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if downloading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Palette.secondaryInk)
                    .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                    .accessibilityLabel("Downloading file")
            } else {
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Metrics.rowCardMinHeight - Space.md * 2)
        .contentShape(.rect)
    }
}
#endif
