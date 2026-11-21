#if canImport(UIKit)
import SwiftUI

extension View {
    /// Wires a sheet's unsaved state: the swipe-down is blocked, and the scaffold's close button
    /// asks "Discard changes?" before dismissing.
    func sheetDirty(_ isDirty: Bool) -> some View {
        modifier(SheetDirtyModifier(isDirty: isDirty))
    }
}
/// One sheet chrome: a native iOS 26 navigation bar (glass close/confirm), the title, the detents
/// and the background. Pushed pages go through the caller's `navigationDestination`.
struct SheetScaffold<Content: View>: View {
    private let title: String
    private let detents: SheetDetents
    private let confirm: SheetConfirm?
    private let onClose: (() -> Void)?
    private let content: Content

    @Environment(\.dismiss) private var dismiss
    @State private var isDirty = false
    @State private var asksDiscard = false

    init(
        _ title: String,
        detents: SheetDetents = .large,
        confirm: SheetConfirm? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detents = detents
        self.confirm = confirm
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .background(Palette.background)
                .scrollContentBackground(.hidden)
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .onPreferenceChange(SheetDirtyKey.self) { isDirty = $0 }
        }
        .presentationDetents(detents.presentationDetents)
        .presentationDragIndicator(detents.dragIndicator)
        .presentationBackground(Palette.background)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close, action: requestClose)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("sheet.close.\(title)")
                // On the close button, so the dialog animates out of the control that asked.
                .confirmationDialog(
                    "Discard changes?", isPresented: $asksDiscard, titleVisibility: .visible
                ) {
                    Button("Discard changes", role: .destructive) { close() }
                    Button("Keep editing", role: .cancel) {}
                }
        }
        if let confirm {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) {
                    confirm.action()
                } label: {
                    Text(confirm.title ?? "Done")
                }
                .disabled(!confirm.isEnabled || confirm.isWorking)
                .accessibilityIdentifier(confirm.identifier ?? "sheet.confirm")
                .overlay {
                    if confirm.isWorking { ProgressView().controlSize(.small) }
                }
            }
        }
    }

    private func requestClose() {
        if isDirty { asksDiscard = true } else { close() }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}
#Preview("Large, light") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScaffold("Sheet title", detents: .large) {
                Text("Content").foregroundStyle(Palette.ink)
            }
            .preferredColorScheme(.light)
        }
}
#Preview("Large, dark") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScaffold("Sheet title", detents: .large) {
                Text("Content").foregroundStyle(Palette.ink)
            }
            .preferredColorScheme(.dark)
        }
}
#Preview("Medium large with confirm") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScaffold(
                "Sheet title", detents: .mediumLarge,
                confirm: SheetConfirm("Save", isEnabled: true, isWorking: false) {}
            ) {
                Text("Content").foregroundStyle(Palette.ink)
            }
        }
}
#Preview("Dirty") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScaffold("Sheet title", detents: .medium, confirm: SheetConfirm("Save", isWorking: true) {}) {
                Text("Content").foregroundStyle(Palette.ink).sheetDirty(true)
            }
        }
}
#endif
