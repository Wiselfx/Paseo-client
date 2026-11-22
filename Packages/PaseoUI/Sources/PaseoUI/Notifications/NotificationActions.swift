#if canImport(UIKit)
import SwiftUI

/// What Settings asks of the app's notification layer: OS permission and the upstream test
/// notification, without PaseoUI importing UserNotifications. The app's notification coordinator
/// adopts it and is installed once at the composition root.
///
/// An object, not stored closures: the environment compares it by identity, so its readers update
/// only when a different object is installed (a closure can't be compared, so every re-created
/// one counted as a change).
@MainActor
public protocol NotificationActions: AnyObject {
    /// Asks the OS for notification permission; the outcome shows up in the OS settings.
    func requestPermission()
    /// Posts the test notification; false when it could not be handed to the OS.
    func sendTestNotification() async -> Bool
}

extension EnvironmentValues {
    /// The app's notification actions. Nil in previews and tests: the permission request does
    /// nothing and the test reports failure.
    @Entry public var notificationActions: (any NotificationActions)?
}
#endif
