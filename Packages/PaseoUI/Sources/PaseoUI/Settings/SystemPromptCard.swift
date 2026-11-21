#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The editable prompt card on the Agents page: a title, a growing text field and a Done button
/// while the draft differs from the saved text. The page owns the draft and focus, because its
/// keyboard Done button saves the same draft.
struct SystemPromptCard: View {
    let title: String
    let placeholder: String
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    let saving: Bool
    let dirty: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
            TextField(placeholder, text: $draft, axis: .vertical)
                .font(.paseo(.codeSmall))
                .lineLimit(3...12)
                .padding(Space.md)
                .background(Palette.background.opacity(0.55), in: .rect(cornerRadius: Radius.md))
                .focused(focused)
            if dirty {
                HStack {
                    Spacer(minLength: Space.sm)
                    Button(action: onSave) {
                        Text(saving ? "Saving…" : "Done")
                            .font(.paseo(.callout, weight: .semibold))
                    }
                    .disabled(saving)
                }
            }
        }
        .padding(Space.lg)
    }
}
#endif
