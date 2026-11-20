#if canImport(UIKit)
import SwiftUI

/// Lets Settings ask the app layer for OS notification permission without importing
/// UserNotifications here. The app installs the real action at the composition root; previews and
/// tests fall back to a no-op.
public struct NotificationPermissionActionKey: EnvironmentKey {
    public static let defaultValue: @Sendable () -> Void = {}
}

public extension EnvironmentValues {
    var notificationPermissionAction: @Sendable () -> Void {
        get { self[NotificationPermissionActionKey.self] }
        set { self[NotificationPermissionActionKey.self] = newValue }
    }
}
#endif
