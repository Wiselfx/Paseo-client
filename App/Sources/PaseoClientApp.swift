import SwiftUI

@main
struct PaseoClientApp: App {
    @State private var model = AppModel()
    @State private var notifications = NotificationCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView(model: model, notifications: notifications)
        }
    }
}
