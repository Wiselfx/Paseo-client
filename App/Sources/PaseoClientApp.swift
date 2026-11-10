import PaseoUI
import SwiftUI

@main
struct PaseoClientApp: App {
    @State private var model = AppModel()
    @State private var notifications = NotificationCoordinator()

    init() {
        // Once, synchronously, before the first frame (R11 §1).
        ClaudeFontResources.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, notifications: notifications)
        }
    }
}
