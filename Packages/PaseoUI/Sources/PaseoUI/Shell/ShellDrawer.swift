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
    /// Called once per committed change, so the shell can mirror it for accessibility and pausing.
    var onStateChange: ((Surface) -> Void)?
    /// The sidebar's search route, called by ⌘K. The sidebar sets it.
    var onSearch: (() -> Void)?
    /// A new session, called by ⌘N.
    var onNewSession: (() -> Void)?

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

/// Which of its two facts a shell surface is in (W1): covered by another surface, and on screen
/// (the panel). The container owns one per surface and flips the fields at the start and end of a
/// motion. They are read through `\.isSurfaceObscured` / `\.isPanelVisible`, so only the views that
/// read them (status dots, loaders, the crab, the panel's page mount) re-evaluate. Before, the
/// container re-assigned each hosting controller's whole `rootView` with new environment values, and
/// every root re-ran its bodies (sidebar, composer, transcript chrome) at the first and last frame
/// of every drawer motion: a 30 to 60 ms main-thread stall at the settle.
///
/// Not main-actor isolated, so the environment getters can read it; written on the main thread
/// only, by `ShellContainerController`.
@Observable
final class SurfaceFlags: @unchecked Sendable {
    var obscured = false
    var panelVisible = false
}

private struct SurfaceFlagsKey: EnvironmentKey {
    static let defaultValue: SurfaceFlags? = nil
}

private struct ShellDrawerKey: EnvironmentKey {
    static let defaultValue: ShellDrawer? = nil
}

private struct PanelVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The shell's drawer bridge; nil outside the shell.
    var shellDrawer: ShellDrawer? {
        get { self[ShellDrawerKey.self] }
        set { self[ShellDrawerKey.self] = newValue }
    }

    /// True while the workspace panel is on screen or moving. The panel mounts its page content
    /// on this instead of on every progress frame (P5-D).
    var isPanelVisible: Bool {
        get { surfaceFlags?.panelVisible ?? self[PanelVisibleKey.self] }
        set { self[PanelVisibleKey.self] = newValue }
    }

    /// The shell container's observable flags for this root; nil outside the shell.
    var surfaceFlags: SurfaceFlags? {
        get { self[SurfaceFlagsKey.self] }
        set { self[SurfaceFlagsKey.self] = newValue }
    }
}
#endif
