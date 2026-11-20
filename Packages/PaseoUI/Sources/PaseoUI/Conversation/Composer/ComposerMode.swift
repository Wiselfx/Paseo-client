#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What the composer is writing into.
enum ComposerMode {
    /// An open agent: the text is `store.draft`, and send goes through the conversation.
    case conversation
    /// A new session, before its agent exists: the text is `draft.text`.
    case draft(DraftSession)
}
#endif
