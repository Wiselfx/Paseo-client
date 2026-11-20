#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Items

/// One row of the transcript's collection view. Turns are keyed by their id; the rest are singletons.
enum TranscriptItemID: Hashable {
    case historyStart
    case turn(String)
    case permissions
    case resolvedPermissions
    case backgroundWork

    /// The singletons' own pools. Turns borrow a slot instead (`TranscriptEngine.reuseIdentifier(for:)`).
    var reuseIdentifier: String {
        switch self {
        case .historyStart: "transcript.history"
        case .turn(let id): "transcript.turn." + id
        case .permissions: "transcript.permissions"
        case .resolvedPermissions: "transcript.resolved"
        case .backgroundWork: "transcript.background"
        }
    }
}
#endif
