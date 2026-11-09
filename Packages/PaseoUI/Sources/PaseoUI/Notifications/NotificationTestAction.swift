#if canImport(UIKit)
import SwiftUI

/// Lets Settings post the upstream test notification without importing
/// UserNotifications here. The app installs the real action at the composition root;
/// previews and tests fall back to a no-op that reports failure.
public struct NotificationTestActionKey: EnvironmentKey {
    public static let defaultValue: @Sendable () async -> Bool = { false }
}

public extension EnvironmentValues {
    var notificationTestAction: @Sendable () async -> Bool {
        get { self[NotificationTestActionKey.self] }
        set { self[NotificationTestActionKey.self] = newValue }
    }
}

/// The notification the test posts. Wording is upstream's
/// (`desktop.permissions.testNotification.title/body`, en.ts:1591-1592).
public enum NotificationTestContent {
    public static let title = "Paseo notification test"
    public static let body = "If you can see this, desktop notifications work."
}
#endif
