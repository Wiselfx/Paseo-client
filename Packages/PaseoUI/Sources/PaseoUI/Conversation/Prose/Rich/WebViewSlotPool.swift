#if canImport(UIKit)
import OSLog
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// How many live `WKWebView`s the app may hold (§0: at most 2). Two cards scrolling into
/// view at once is the most a reader can look at; the rest draw their snapshot. The
/// artifact page leases one slot while open, which outranks transcript slots (G4/G5):
/// transcript web cards release theirs and fall back to snapshots.
@MainActor
final class WebViewSlotPool {
    static let shared = WebViewSlotPool()
    private(set) var live = 0
    private let limit = 2

    /// True when a slot was taken; the caller must `release()` it.
    func claim() -> Bool {
        guard live < limit else { return false }
        live += 1
        debugLog()
        return true
    }

    func release() {
        live = max(0, live - 1)
        debugLog()
    }

    /// The DEBUG counter that proves the §0 budget: every claim and release logs the
    /// live count, so a 20-card scroll can be audited without Instruments.
    private func debugLog() {
        #if DEBUG
        print("[webview-slots] live=\(live)/\(limit)")
        #endif
    }
}
#endif
