import Foundation
import UserNotifications

/// The UNUserNotificationCenter delegate must be an NSObject. It carries no state beyond the
/// callbacks the coordinator installs once before any callback can run.
final class NotificationDelegateProxy: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    /// The raw response plus its completion, for the coordinator to answer
    /// (possibly after async work) and complete exactly once.
    var onResponse:
        (@Sendable (String, [String: String], @escaping @Sendable () -> Void) -> Void)?

    /// Foreground notifications stay in Notification Center: no banner, no sound. Upstream keeps
    /// them for stale presence information — the push was queued before this app reattached, so
    /// the thing it announces is often over by the time it arrives (docs/notifications.md:53-54,
    /// `packages/app/src/notification-open/source.native.ts:12-20`: `shouldShowBanner: false`,
    /// `shouldShowList: true`, `shouldPlaySound: false`).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // The coordinator answers (possibly after async work) and completes
        // exactly once; without a handler this falls through to the tap path.
        // The coordinator installs `onResponse` in its init, before any callback.
        guard let onResponse else {
            completionHandler()
            return
        }
        var info: [String: String] = [:]
        for (key, value) in response.notification.request.content.userInfo {
            guard let key = key as? String, let value = value as? String else { continue }
            info[key] = value
        }
        let completion = CompletionBox(completionHandler)
        onResponse(response.actionIdentifier, info) { completion.call() }
    }
}
