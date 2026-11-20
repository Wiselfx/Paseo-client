#if canImport(UIKit)
import PaseoStore
import QuartzCore
import SwiftTerm
import SwiftUI
import UIKit

/// The terminal's canvas: the same panel fill as every other workspace tab, resolved for the
/// traits the emulator currently sees (E2b §3).
@MainActor
enum PaseoTerminalBackground {
    /// Sets the panel fill only when the scheme it resolves for changed: dark, light or pure
    /// black. Every other call is a two-field compare.
    static func apply(to view: TerminalView, coordinator: PaseoTerminalCoordinator) {
        let traits = view.traitCollection
        let key = PaseoTerminalCoordinator.BackgroundKey(
            style: traits.userInterfaceStyle, pureBlack: traits.pureBlack)
        guard coordinator.appliedBackground != key else { return }
        coordinator.appliedBackground = key
        view.nativeBackgroundColor = UIColor(Palette.panel).resolvedColor(with: traits)
    }
}
#endif
