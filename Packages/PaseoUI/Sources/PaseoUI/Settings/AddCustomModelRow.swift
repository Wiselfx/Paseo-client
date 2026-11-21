#if canImport(UIKit)
import SwiftUI

/// The text field and Add button that end the custom models group.
struct AddCustomModelRow: View {
    @Binding var modelID: String
    let onAdd: () -> Void

    private var isEmpty: Bool {
        modelID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(spacing: Space.md) {
            TextField("Model ID", text: $modelID)
                .font(.paseo(.code))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { onAdd() }
            Button("Add") {
                Haptics.light()
                onAdd()
            }
            .font(.paseo(.callout, weight: .semibold))
            .foregroundStyle(isEmpty ? Palette.secondaryInk : Palette.ink)
            .disabled(isEmpty)
            .accessibilityIdentifier("settings.providers.custom.add")
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: 52)
    }
}
#endif
