#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import UIKit

/// Builds the screen's `ChatController` on first use, once. A throwaway holder (one per `init`)
/// costs a closure; only the holder `@State` keeps is ever asked. The build runs inside an
/// observation scope of its own, so the reads the controller's setup makes (agent, workspace,
/// checkout) never become dependencies of the view body that happened to ask first.
@MainActor
final class ChatControllerHolder {
    private let make: () -> ChatController
    private var built: ChatController?

    init(make: @escaping () -> ChatController) {
        self.make = make
    }

    var controller: ChatController {
        if let built { return built }
        let controller = withObservationTracking({ make() }, onChange: {})
        built = controller
        return controller
    }
}
#endif
