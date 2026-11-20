#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

enum ClaudeChatSheet: String, Identifiable {
    case controls
    case subagents
    case backgroundWork
    case turnNav
    case media
    var id: String { rawValue }
}
#endif
