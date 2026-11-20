#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The transcript's content as values: built by `TranscriptView` from the store, applied by the engine.
struct TranscriptModel {
    var items: [TranscriptItemID] = []
    var entries: [TranscriptEntry] = []
}
#endif
