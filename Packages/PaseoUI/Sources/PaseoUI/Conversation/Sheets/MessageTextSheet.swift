#if canImport(UIKit)
import SwiftUI

/// "Select text" for one message bubble (UX spec §4.3): the bubble's words as plain selectable
/// text in a sheet.
///
/// Selection lives here instead of inside the filled bubble: `.textSelection` applied before the
/// bubble's padding and fill painted a full-width rectangle inside the bubble (B12).
struct MessageTextSheet: View {
    let text: String

    var body: some View {
        SheetScaffold("Select text", detents: .mediumLarge) {
            ScrollView {
                Text(text)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.lg)
            }
        }
    }
}
#endif
