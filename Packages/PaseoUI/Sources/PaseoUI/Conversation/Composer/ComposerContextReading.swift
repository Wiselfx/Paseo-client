#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One reading of the window as a plain value: what the ring draws and what it compares on.
struct ComposerContextReading: Equatable {
    /// 0…100, rounded — the number inside the ring. `nil` while the provider has reported no
    /// window, or only one of the two figures: a half-known window gets the empty track, never a
    /// fabricated percentage.
    let percent: Int?

    init(_ usage: ContextUsage?) {
        guard let usage, let percent = usage.percentUsed, usage.usedTokens != nil,
            usage.maxTokens != nil
        else {
            self.percent = nil
            return
        }
        self.percent = min(100, max(0, Int(percent.rounded())))
    }
}
#endif
