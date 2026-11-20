#if canImport(UIKit)
import SwiftUI

/// The notification the test posts. Wording is upstream's
/// (`desktop.permissions.testNotification.title/body`, en.ts:1591-1592).
public enum NotificationTestContent {
    public static let title = "Paseo notification test"
    public static let body = "If you can see this, desktop notifications work."
}
#endif
