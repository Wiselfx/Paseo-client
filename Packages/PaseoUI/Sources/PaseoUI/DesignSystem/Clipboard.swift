#if canImport(UIKit)
import UIKit

/// The one way the app writes the pasteboard.
enum Clipboard {
    @MainActor static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    /// Copy and confirm through the shell's toast, when there is one.
    @MainActor static func copy(_ text: String, toast: ToastCenter?) {
        copy(text)
        toast?.show("Copied")
    }
}
#endif
