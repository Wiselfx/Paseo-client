import PaseoUI
import SwiftUI

@main
struct PaseoClientApp: App {
    @State private var model = AppModel()
    @State private var notifications = NotificationCoordinator()

    init() {
        // Once, synchronously, before the first frame (R11 §1).
        ClaudeFontResources.register()
        // Notification answers never depend on a view: the handlers are set once
        // at launch (G19 review). With `.authenticationRequired` and no
        // `.foreground` option the system answers without opening the app, so a
        // `RootView.onChange` would usually never run before suspension.
        notifications.performPermissionAction = { [weak model] action in
            await model?.performPermissionAction(action) ?? false
        }
        notifications.permissionRequestProvider = { [weak model] agentId in
            model?.latestSimplePermissionRequest(for: agentId)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, notifications: notifications)
        }
    }
}
