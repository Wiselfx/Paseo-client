#if canImport(UIKit)
import SwiftUI

/// The password row of the Connect form. Return connects when the form is complete.
struct ConnectSecureField: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let identifier: String
    let canConnect: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ConnectFieldSymbol(symbol: "lock")
            VStack(alignment: .leading, spacing: 2) {
                // The field's own title is what VoiceOver reads; the visible caption would repeat it.
                Text(title)
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityHidden(true)
                SecureField(
                    title, text: $text,
                    prompt: Text(prompt).foregroundStyle(Palette.captionInk)
                )
                .font(.paseo(.body))
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit { if canConnect { onConnect() } }
                .accessibilityIdentifier(identifier)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
#endif
