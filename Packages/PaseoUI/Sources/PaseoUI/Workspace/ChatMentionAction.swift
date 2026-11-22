#if canImport(UIKit)
import SwiftUI

/// "Mention in chat" for the workspace panel's pages: inserts `@relative/path ` into the composer on
/// screen (see `ShellView`). The shell creates one for its lifetime and installs its handler at
/// startup, the same way it wires `ShellDrawer`.
///
/// A class rather than an environment closure: the environment compares it by identity, so the
/// pages that read it update only when the object changes, never because a closure was re-created.
@MainActor
final class ChatMentionAction {
    /// Installed by the shell once it appears; nil until then, which makes a mention a no-op.
    var perform: ((String) -> Void)?

    func callAsFunction(_ text: String) {
        perform?(text)
    }
}
#endif
