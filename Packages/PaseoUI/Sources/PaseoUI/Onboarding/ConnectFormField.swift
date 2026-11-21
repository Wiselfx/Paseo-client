#if canImport(UIKit)
import SwiftUI

/// One labelled text row of the Connect form: a glyph, a caption and the field.
struct ConnectFormField: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let symbol: String
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    let identifier: String

    var body: some View {
        HStack(spacing: 12) {
            ConnectFieldSymbol(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                // The field's own title is what VoiceOver reads; the visible caption would repeat it.
                Text(title)
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityHidden(true)
                TextField(
                    title, text: $text,
                    prompt: Text(prompt).foregroundStyle(Palette.captionInk)
                )
                .font(.paseo(.body))
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(identifier)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
#endif
