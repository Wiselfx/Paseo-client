#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One file's diff, opened from the turn changes card (G6 C11): the tool call's own
/// unified diff when this conversation has one, else the file viewer.
struct ClaudeDiffDocument: Identifiable {
    var id: String { path }
    let path: String
    let unifiedDiff: String?
    let old: String?
    let new: String?

    /// The file name for the sheet title.
    var fileName: String {
        (path as NSString).lastPathComponent
    }
}
#endif
