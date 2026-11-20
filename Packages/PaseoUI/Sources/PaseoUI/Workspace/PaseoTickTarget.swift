#if canImport(UIKit)
import PaseoStore
import QuartzCore
import SwiftTerm
import SwiftUI
import UIKit

/// The display link's target. It holds the coordinator weakly, so a link that outlives its view
/// never owns it.
@MainActor
final class PaseoTickTarget: NSObject {
    weak var coordinator: PaseoTerminalCoordinator?

    @objc func tick(_ link: CADisplayLink) {
        coordinator?.flushPending()
    }
}
#endif
