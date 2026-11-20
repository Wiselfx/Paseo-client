#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The display link's target. It holds the view weakly, so the link (which retains its target)
/// never keeps a removed meter alive.
@MainActor
final class WaveformTickTarget: NSObject {
    weak var view: WaveformMeterView?

    init(view: WaveformMeterView) {
        self.view = view
    }

    @objc func tick(_ link: CADisplayLink) {
        view?.tick(link)
    }
}
#endif
