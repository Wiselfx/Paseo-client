#if canImport(UIKit)
import SwiftUI

// MARK: - Paste

/// Paste a pairing link: `PasteButton` (no pasteboard prompt) or a text field, through the
/// same offer parser as scan. The link is never logged.
public struct PastePairingSheet: View {
    /// A failure from the last attempt (parse or connect), shown when the paste step is
    /// re-presented with the error (S6).
    public var error: String?
    /// Called once with the accepted raw payload, already trimmed.
    public var onPasted: (String) -> Void

    public init(error: String? = nil, onPasted: @escaping (String) -> Void) {
        self.error = error
        self.onPasted = onPasted
    }

    @State private var text = ""
    @State private var invalid = false

    public var body: some View {
        SheetScaffold("Paste pairing link", detents: .large) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Treat this pairing link like a password. Anyone with it can access this host.")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                // Prompt-free PasteButton (system label): reads the pasteboard on tap.
                PasteButton(payloadType: String.self) { strings in
                    text = strings.first ?? ""
                    invalid = false
                    submit()
                }
                .font(.paseo(.callout, weight: .medium))
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pairing.paste.button")
                TextField("Pairing link", text: $text)
                    .font(.paseo(.callout))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Palette.chip, in: .rect(cornerRadius: Radius.md))
                    .onSubmit { submit() }
                    .accessibilityIdentifier("pairing.paste.field")
                Button {
                    submit()
                } label: {
                    Text("Connect")
                        .font(.paseo(.callout, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.ink)
                .accessibilityIdentifier("pairing.paste.connect")
                if invalid {
                    Text("That link doesn't look right.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                }
                if let error, !invalid {
                    Text(error)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Same acceptance rule as the scanner; the parse itself happens on Connect.
        guard PairingLink.looksValid(trimmed) else {
            invalid = true
            return
        }
        onPasted(trimmed)
    }
}
#endif
