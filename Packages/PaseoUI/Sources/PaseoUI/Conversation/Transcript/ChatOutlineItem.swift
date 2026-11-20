#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// One prompt in the chat outline: the daemon's index entry, or a loaded turn in fallback.
struct ChatOutlineItem: Identifiable, Hashable {
    /// The prompt's timeline position (its user row's `seqStart`).
    let seq: Int
    /// What the rail's preview bubble and the sheet show.
    let preview: String
    var id: Int { seq }
}
#endif
