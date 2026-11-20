import SwiftUI
import UIKit

/// Whether the pasteboard holds images, asked once and refreshed when it can have changed (W1).
/// `UIPasteboard.hasImages` is a round trip to the pasteboard daemon, and UIKit asks
/// `canPerformAction(paste:)` repeatedly while the field is edited and the composer body asked it on
/// every pass: the sampled keystroke windows were waiting in `mach_msg` under `canPerformAction`.
@MainActor
final class PasteboardImageState {
    static let shared = PasteboardImageState()
    private var cached: Bool?

    var hasImages: Bool {
        if let cached { return cached }
        let value = UIPasteboard.general.hasImages
        cached = value
        return value
    }

    private init() {
        for name in [UIPasteboard.changedNotification, UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PasteboardImageState.shared.cached = nil }
            }
        }
    }
}
