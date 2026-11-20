#if canImport(UIKit)
import SwiftUI
import UIKit

/// The UIKit drawer container (R5 §1): three hosting controllers, one pan recognizer, one
/// animator. SwiftUI hands it the three roots and never sees a progress value, so a drag writes
/// `transform` and `alpha` on the layer tree and evaluates no body.
struct ShellContainer: UIViewControllerRepresentable {
    let drawer: ShellDrawer
    /// The roots are assigned again only when this changes (`ShellView.rootsKey`).
    let rootsKey: ShellRootsKey
    let sidebar: AnyView
    let main: AnyView
    let panel: AnyView

    func makeUIViewController(context: Context) -> ShellContainerController {
        let controller = ShellContainerController(drawer: drawer)
        controller.rootsKey = rootsKey
        controller.setRoots(sidebar: sidebar, main: main, panel: panel)
        return controller
    }

    func updateUIViewController(_ controller: ShellContainerController, context: Context) {
        guard controller.rootsKey != rootsKey else { return }
        controller.rootsKey = rootsKey
        controller.setRoots(sidebar: sidebar, main: main, panel: panel)
    }
}
#endif
