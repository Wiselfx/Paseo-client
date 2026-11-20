#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// What a cell draws. A turn is the equatable `TurnRow`; the rest observe the store themselves.
enum TranscriptEntry: Equatable {
    case historyStart
    case turn(TurnRow)
    case permissions
    case resolvedPermissions
    case backgroundWork

    nonisolated static func == (lhs: TranscriptEntry, rhs: TranscriptEntry) -> Bool {
        switch (lhs, rhs) {
        case (.historyStart, .historyStart), (.permissions, .permissions),
            (.resolvedPermissions, .resolvedPermissions), (.backgroundWork, .backgroundWork):
            return true
        case (.turn(let a), .turn(let b)):
            return a == b
        default:
            return false
        }
    }
}
#endif
