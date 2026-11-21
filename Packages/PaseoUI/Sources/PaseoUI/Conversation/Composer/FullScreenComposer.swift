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
        // A system navigation bar, not a hand-built one: it takes Liquid Glass and the scroll-edge
        // treatment, moves with the window on iPhone Duo, and grows with Dynamic Type.
        NavigationStack {
            TextEditor(text: $draft)
                .font(.paseo(.body))
                .foregroundStyle(Palette.ink)
                .tint(Palette.accentInk)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .focused($focused)
                .accessibilityIdentifier("composer.fullscreen.editor")
                .background(Palette.background.ignoresSafeArea())
                .navigationTitle("Message")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Done keeps the draft; Send sends it.
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", systemImage: "checkmark", action: dismissKeepingDraft)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(
                            isRunning ? "Send and steer" : "Send", systemImage: "arrow.up",
                            action: sendAndDismiss
                        )
                        .disabled(trimmedEmpty)
                        .accessibilityIdentifier("composer.fullscreen.send")
                    }
                }
        }
        .foregroundStyle(Palette.ink)
        .onAppear { focused = true }
    }

    private func sendAndDismiss() {
        onSend()
        dismiss()
    }

    private func dismissKeepingDraft() {
        dismiss()
    }
}
#endif
