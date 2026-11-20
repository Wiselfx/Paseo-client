#if canImport(UIKit)
import Observation
import SwiftUI

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
#endif
