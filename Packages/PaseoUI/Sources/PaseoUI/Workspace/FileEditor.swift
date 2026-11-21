#if canImport(UIKit)
import SwiftUI

/// A plain monospaced TextEditor, deliberately without syntax highlighting.
///
/// The text arrives as a binding that this view alone reads, and the unsaved-edits flag is
/// written back from here, so a keystroke re-evaluates this view and not the whole file viewer.
struct FileEditor: View {
    @Binding var text: String
    /// The version of the file the edits are measured against.
    let baseline: String
    @Binding var isDirty: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.paseo(.codeSmall))
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.codeSurface)
            .accessibilityLabel("Edit file contents")
            .onChange(of: text) { updateDirty() }
            .onChange(of: baseline) { updateDirty() }
    }

    private func updateDirty() {
        let dirty = text != baseline
        if isDirty != dirty { isDirty = dirty }
    }
}
#endif
