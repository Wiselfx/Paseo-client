#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A rewind awaiting the can't-undo confirmation (M7d).
struct PendingRewind: Identifiable {
    let messageId: String
    let scope: RewindScope
    var id: String { "\(messageId)/\(scope)" }
}
#endif
