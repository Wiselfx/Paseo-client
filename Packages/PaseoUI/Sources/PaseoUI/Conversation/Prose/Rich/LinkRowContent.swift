#if canImport(UIKit)
import SwiftUI
import UIKit

/// The text-only presentation of a link card, used until (or unless) a hero image exists: the
/// site icon or a link glyph, the title, and the shortened URL.
struct LinkRowContent: View {
    let icon: UIImage?
    let title: String
    let meta: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let icon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: Metrics.linkIconSize, height: Metrics.linkIconSize)
                    .clipShape(.rect(cornerRadius: Radius.sm, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.chip)
                    .frame(width: Metrics.linkIconSize, height: Metrics.linkIconSize)
                    .overlay {
                        Image(systemName: "link")
                            .font(.glyph(.regular))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.paseo(.footnote, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(meta)
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
    }
}
#endif
