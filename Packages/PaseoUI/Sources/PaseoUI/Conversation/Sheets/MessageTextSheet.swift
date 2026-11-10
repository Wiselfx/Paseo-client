#if canImport(UIKit)
import SwiftUI

/// "Select text" for one message bubble (UX spec §4.3): the bubble's words as plain selectable
/// text in a sheet.
///
/// Selection lives here instead of inside the filled bubble: `.textSelection` applied before the
/// bubble's padding and fill painted a full-width rectangle inside the bubble (B12).
struct MessageTextSheet: View {
    let text: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Select text", close: { dismiss() })
            ScrollView {
                Text(text)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
        }
        .background(Palette.background)
        .presentationDetents([.medium, .large])
    }
}
#endif
