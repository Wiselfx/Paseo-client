import Foundation
import Observation
import PaseoStore
import UserNotifications

/// Posts local notifications for `AttentionCenter` intents and turns a notification tap back into
/// an `AttentionTarget` for the shell.
///
/// This is the app's only UserNotifications code. It deliberately does not register for remote
/// push: there is no relay or APNs provider in this client (see docs/research/10-notifications.md).
@MainActor @Observable
final class NotificationCoordinator {
    /// A tap waiting for the shell to route it. The shell clears it after selecting.
    var pendingTarget: AttentionTarget?

    private let proxy: NotificationDelegateProxy

    private static let promptedKey = "paseo.notifications.prompted"

    init() {
        let proxy = NotificationDelegateProxy()
        self.proxy = proxy
        proxy.onTap = { [weak self] target in
            Task { @MainActor in self?.pendingTarget = target }
        }
        UNUserNotificationCenter.current().delegate = proxy
    }

    /// User preference. Defaults to on; the permission prompt happens on first use rather than
    /// at launch.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: AttentionNotificationKeys.enabled) as? Bool ?? true
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Requests permission only when the system has not decided yet. Called from Settings when
    /// the toggle is switched on, and from the first attention event.
    @discardableResult
    func requestAuthorization() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            UserDefaults.standard.set(true, forKey: Self.promptedKey)
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        default:
            return false
        }
    }

    /// Posts every intent. Silently drops them when notifications are off or permission is denied.
    func deliver(_ intents: [AttentionIntent]) async {
        guard !intents.isEmpty, isEnabled else { return }
        guard await ensureAuthorization() else { return }
        for intent in intents { post(intent) }
    }

    private func ensureAuthorization() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            // The first agent that needs you is the prompt's moment, but never ask twice.
            guard !UserDefaults.standard.bool(forKey: Self.promptedKey) else { return false }
            return await requestAuthorization()
        default:
            return false
        }
    }

    private func post(_ intent: AttentionIntent) {
        let content = UNMutableNotificationContent()
        content.title = intent.title
        content.body = intent.body
        content.sound = .default
        content.threadIdentifier = "paseo.attention"
        var userInfo: [AnyHashable: Any] = [:]
        for (key, value) in intent.target.userInfo { userInfo[key] = value }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: intent.id, content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }
}

/// The UNUserNotificationCenter delegate must be an NSObject. It carries no state beyond the tap
/// closure, which the coordinator installs once before any callback can run.
private final class NotificationDelegateProxy: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    var onTap: (@Sendable (AttentionTarget) -> Void)?

    /// Foreground notifications are the point of this ticket (the agent is rarely on screen);
    /// `AttentionCenter` already suppressed the conversation the user is reading.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        var info: [String: String] = [:]
        for (key, value) in response.notification.request.content.userInfo {
            guard let key = key as? String, let value = value as? String else { continue }
            info[key] = value
        }
        let target = AttentionTarget(userInfo: info)
        completionHandler()
        guard let target else { return }
        onTap?(target)
    }
}
