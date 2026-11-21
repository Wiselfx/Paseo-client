#if canImport(UIKit)
import SwiftUI

/// The History screen's title filter: a chip-filled field with a clear button. The caller owns
/// the text and debounces it.
struct HistorySearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(.small))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
            TextField("Search history", text: $text)
                .font(.paseo(.callout))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("history.search")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.glyph(.small))
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.md)
        // A minimum, not a fixed height: the field's text grows with Dynamic Type.
        .frame(minHeight: 44)
        .background(Palette.chip, in: .rect(cornerRadius: Radius.sm))
        .padding(.horizontal, Space.lg)
        .padding(.bottom, Space.sm)
    }
}
#endif
