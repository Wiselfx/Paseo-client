#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import Synchronization
import UIKit
import UniformTypeIdentifiers

/// A recorded jump intent: the transcript performs the scroll (it owns the scroll handles).
struct TranscriptJump: Equatable {
    var id: String
}
#endif
