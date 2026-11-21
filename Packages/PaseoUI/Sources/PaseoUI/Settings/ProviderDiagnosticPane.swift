#if canImport(UIKit)
import SwiftUI

/// The diagnostic text, mono and selectable in a bounded scroll view, with a copy button.
struct ProviderDiagnosticPane: View {
    let text: String
    let isFailure: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(text.isEmpty ? "The host returned an empty diagnostic." : text)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(isFailure ? Palette.failureInk : Palette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 220)
            HStack {
                CopyButton(text: text, label: "Copy diagnostic")
                    .accessibilityIdentifier("settings.providers.diagnostic.copy")
                Spacer(minLength: 0)
            }
        }
        .padding(Space.md)
    }
}
#endif
