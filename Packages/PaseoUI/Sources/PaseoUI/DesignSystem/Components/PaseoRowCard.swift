#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import UIKit

/// The row-card layout (G1 §1.1): a 56 pt minimum row — glyph, title, meta, one trailing
/// accessory. Text containers use `minHeight`, never `height`, so Dynamic Type grows the row.
struct PaseoRowCard<Accessory: View>: View {
    let glyph: String
    let title: String
    let meta: String?
    let accessory: Accessory

    init(glyph: String, title: String, meta: String? = nil, accessory: Accessory) {
        self.glyph = glyph
        self.title = title
        self.meta = meta
        self.accessory = accessory
    }

    var body: some View {
        PaseoCard(content:
            HStack(spacing: Space.sm) {
                Image(systemName: glyph)
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(minWidth: Metrics.hitSize - Space.md, alignment: .center)
                    .accessibilityHidden(true)
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
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                accessory
            }
            .frame(minHeight: Metrics.rowCardMinHeight - Space.md * 2)
        )
    }
}
extension PaseoRowCard where Accessory == EmptyView {
    init(glyph: String, title: String, meta: String? = nil) {
        self.init(glyph: glyph, title: title, meta: meta, accessory: EmptyView())
    }
}
#endif
