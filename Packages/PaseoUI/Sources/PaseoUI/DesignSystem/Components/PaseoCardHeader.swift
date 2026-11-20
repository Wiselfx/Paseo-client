#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import UIKit

/// The standard header strip: an optional 17 pt glyph, a 1–2 line title, an optional meta line.
/// A value (R-2); doubles as the card's accessibility label.
struct PaseoCardHeader: View, Equatable {
    let glyph: String?
    let title: String
    let meta: String?

    init(glyph: String? = nil, title: String, meta: String? = nil) {
        self.glyph = glyph
        self.title = title
        self.meta = meta
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            if let glyph {
                Image(systemName: glyph)
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if let meta {
                    Text(meta)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
