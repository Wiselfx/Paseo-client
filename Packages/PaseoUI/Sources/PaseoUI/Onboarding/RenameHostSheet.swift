#if canImport(UIKit)
import SwiftUI

/// The rename sheet for a saved host. The caller owns the text and decides what saving means.
struct RenameHostSheet: View {
    @Binding var text: String
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            SheetHeader(title: "Rename host", close: onClose)
            // Scrolls so Save stays reachable at accessibility text sizes.
            ScrollView {
                VStack(spacing: 16) {
                    RowGroup {
                        TextField("Label", text: $text)
                            .font(.paseo(.body))
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(onSave)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                            .accessibilityIdentifier("connect.rename.field")
                    }
                    Button {
                        onSave()
                    } label: {
                        Text("Save")
                    }
                    .buttonStyle(.paseoPrimary())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, Space.lg)
                    .accessibilityIdentifier("connect.rename.save")
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.height(260), .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
