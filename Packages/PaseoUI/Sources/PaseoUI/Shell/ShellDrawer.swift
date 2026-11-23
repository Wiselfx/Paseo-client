#if canImport(UIKit)
import Observation
import SwiftUI

/// The shell's drawer bridge: SwiftUI asks for a surface, the container moves it. Views read
/// `state`, never a progress, so nothing in SwiftUI invalidates per frame (R5 §1).
@MainActor
final class ShellDrawer {
    /// Which surface is on top.
    enum Surface: Equatable {
        case none
        case sidebar
        case panel
    }

    /// Committed state only: it changes when a motion ends, never mid-drag.
    private(set) var state: Surface = .none

    /// The turn rail is visible: a trailing-edge pan belongs to the rail, not the panel.
    var trailingEdgeReserved = false
    /// The panel's inner `NavigationStack` is deeper than its root (R7's Files stack).
    var panelHandlesBack = false
    /// Pops one pushed page (a folder, or a file) of the panel's Files stack; nil while the panel
    /// is at its root. The header's back chevron calls it first and closes the panel only when
    /// it is nil, so Back means one level up everywhere.
    var panelPopOne: (() -> Void)?
    /// Called once per committed change, so the shell can mirror it for accessibility and pausing.
    var onStateChange: ((Surface) -> Void)?
    /// The sidebar's search route, called by ⌘K. The sidebar sets it.
    var onSearch: (() -> Void)?
    /// A new session, called by ⌘N.
    var onNewSession: (() -> Void)?
    /// Hides or shows the status bar. The panel's hosting controller is a child of the shell's
    /// container, so its own `statusBarHidden` never reaches the window; the shell applies the
    /// flag at its root instead. Set by `ShellView`.
    var onStatusBarHiddenChange: ((Bool) -> Void)?

    /// The terminal's full screen asks for the status bar to go (and come back).
    func setStatusBarHidden(_ hidden: Bool) {
        onStatusBarHiddenChange?(hidden)
    }

    /// The container, which owns the motion. Weak: the container keeps the drawer alive.
    weak var controller: ShellContainerController?

    func open(_ surface: Surface) {
        controller?.animate(to: surface)
    }

    func close() {
        controller?.animate(to: .none)
    }

    /// ⌘\ and ⌘⇧\: open the surface, or close it when it is already the one on screen.
    func toggle(_ surface: Surface) {
        controller?.animate(to: state == surface ? .none : surface)
    }

    /// The container's commit point.
    func adopt(_ surface: Surface) {
        state = surface
    }
}
extension EnvironmentValues {
    /// The shell's drawer bridge; nil outside the shell.
    @Entry var shellDrawer: ShellDrawer?

    /// The shell container's observable flags for this root; nil outside the shell.
    @Entry var surfaceFlags: SurfaceFlags?

    /// What `isPanelVisible` reads outside the shell, where there are no surface flags.
    @Entry var panelVisibleFallback = false

    /// True while the workspace panel is on screen or moving. The panel mounts its page content
    /// on this instead of on every progress frame (P5-D).
    var isPanelVisible: Bool {
        get { surfaceFlags?.panelVisible ?? panelVisibleFallback }
        set { panelVisibleFallback = newValue }
    }
}
#endif
