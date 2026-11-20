#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Where a fork goes. Upstream's `AssistantForkTarget` (`assistant-fork-menu.tsx:14-15`).
enum ClaudeForkTarget: Sendable {
    case tab
    case workspace
}
#endif
