#if canImport(UIKit)
import SwiftUI
import PaseoStore

/// M8b: the full-height draft editor for long drafts. Shares the composer's draft binding; same
/// Sans as the composer at 17 pt. Done keeps the draft; Send sends it.
struct FullScreenComposer: View {
    @Binding var draft: String
    let isRunning: Bool
    let onSend: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool


    private var trimmedEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Button("Done") { dismiss() }
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .accessibilityLabel("Done")
                Spacer()
                Text("Message")
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button("Send") {
                    onSend()
                    dismiss()
                }
                .font(.paseo(.callout, weight: .semibold))
                .foregroundStyle(trimmedEmpty ? Palette.secondaryInk : Palette.accentInk)
                .disabled(trimmedEmpty)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .accessibilityLabel(isRunning ? "Send and steer" : "Send message")
                .accessibilityIdentifier("composer.fullscreen.send")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            ClaudeDivider()
            TextEditor(text: $draft)
                .font(.paseo(.body))
                .foregroundStyle(Palette.ink)
                .tint(Palette.accentInk)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .focused($focused)
                .accessibilityIdentifier("composer.fullscreen.editor")
        }
        .background(Palette.background.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
        .onAppear { focused = true }
    }
}
#endif
