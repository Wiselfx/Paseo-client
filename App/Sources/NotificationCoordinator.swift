import Foundation
import UIKit
import Observation
import PaseoStore
import PaseoUI
import UserNotifications

/// A notification Allow/Deny answer waiting for the shell to perform. The shell
/// reconnects if needed, sends through the store's permission path, and records
/// the line (which the transcript shows only after the daemon confirms, D8).
/// On failure the shell posts an "Open" fallback instead.
struct PendingPermissionAction: Sendable, Hashable {
    var requestId: String
    var agentId: String
    var hostServerID: String
    var allow: Bool
    var daemonActionId: String
}

/// Posts local notifications for `AttentionCenter` intents and turns a notification tap back into
/// an `AttentionTarget` for the shell.
///
/// This is the app's only UserNotifications code. It deliberately does not register for remote
/// push: there is no relay or APNs provider in this client (see docs/research/10-notifications.md).
@MainActor @Observable
final class NotificationCoordinator {
    /// A tap waiting for the shell to route it. The shell clears it after selecting.
    var pendingTarget: AttentionTarget?
    /// Answers a notification Allow/Deny: reconnects if needed and sends through
    /// the store's permission path. Set once at launch by the composition root
    /// (never by a view). Returns whether the daemon confirmed.
    var performPermissionAction: (@MainActor (PendingPermissionAction) async -> Bool)?
    /// Resolves an agent id to its latest permission request plus the daemon
    /// server id to answer on (or nil). Set once at launch by the composition
    /// root, which owns the session.
    var permissionRequestProvider: ((String) -> (AgentPermissionRequest, String)?)?
    /// The in-flight answer's background task, so expiry and completion end it.
    private var permissionTask: UIBackgroundTaskIdentifier = .invalid

    private let proxy: NotificationDelegateProxy

    private static let promptedKey = "paseo.notifications.prompted"
    static let permissionCategoryID = "paseo.permission"
    static let allowActionID = "paseo.permission.allow"
    static let denyActionID = "paseo.permission.deny"

    init() {
        let proxy = NotificationDelegateProxy()
        self.proxy = proxy
        proxy.onResponse = { [weak self] response, completion in
            Task { @MainActor [weak self] in
                guard let self else { completion(); return }
                await self.handleResponse(response, completion: completion)
            }
        }
        UNUserNotificationCenter.current().delegate = proxy
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.permissionCategoryID,
                actions: [
                    UNNotificationAction(
                        identifier: Self.allowActionID, title: "Allow",
                        options: [.authenticationRequired]),
                    UNNotificationAction(
                        identifier: Self.denyActionID, title: "Deny",
                        options: [.authenticationRequired, .destructive]),
                ],
                intentIdentifiers: [], options: [])
        ])
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

    /// Posts the upstream test notification (Settings → Notifications → Test notification).
    /// Unlike `deliver`, this never prompts: it returns false unless permission is already
    /// granted, so the settings row can report the failure.
    func sendTestNotification() async -> Bool {
        guard isEnabled else { return false }
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: break
        default: return false
        }
        let content = UNMutableNotificationContent()
        content.title = NotificationTestContent.title
        content.body = NotificationTestContent.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "paseo.test-notification", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
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

    /// Actions appear only on simple permission requests (G19): one tool call, no
    /// free-text input, no question options — and only when the reader opted in.
    /// Anything richer keeps the transcript card as its only surface.
    private func post(_ intent: AttentionIntent) {
        // Privacy (§11): agent names stay on the Lock Screen only with opt-in.
        // Off means a generic title/body and no thumbnail — while routing
        // (userInfo) still works, since it is never shown.
        let namesAllowed = UserDefaults.standard.bool(forKey: PaseoSettingsKeys.showAgentNames)
        let content = UNMutableNotificationContent()
        content.title = namesAllowed ? intent.title : "Paseo"
        content.body = namesAllowed ? intent.body : "An agent needs your attention."
        content.sound = .default
        content.threadIdentifier = "paseo.attention"
        var userInfo: [AnyHashable: Any] = [:]
        for (key, value) in intent.target.userInfo { userInfo[key] = value }
        let thumbnail = namesAllowed ? thumbnailSource(for: intent) : nil
        if let agentId = intent.target.agentId,
            UserDefaults.standard.bool(forKey: PaseoSettingsKeys.notificationActions),
            let (request, hostServerID) = permissionRequestProvider?(agentId),
            let mapped = PermissionNotificationMapping.actions(for: request),
            intent.reason == "permission"
        {
            content.categoryIdentifier = Self.permissionCategoryID
            userInfo[Self.requestIdKey] = request.id
            userInfo[Self.agentIdKey] = agentId
            userInfo[Self.hostKey] = hostServerID
            userInfo[Self.allowIdKey] = mapped.allowActionId
            userInfo[Self.denyIdKey] = mapped.denyActionId
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: intent.id, content: content, trigger: nil)
        Task {
            // §11: the thumbnail comes only from the pipeline's caches (memory,
            // then the daemon disk cache) via a temp-file copy. Never a fetch:
            // nothing cached means no image.
            if let thumbnail,
                let fileURL = await Task.detached(priority: .utility, operation: { () -> URL? in
                    guard
                        let data = MediaPipeline.cachedNotificationThumbnail(
                            remoteURL: thumbnail.remoteURL, daemonPath: thumbnail.daemonPath,
                            workspaceID: thumbnail.workspaceID),
                        !data.isEmpty
                    else { return nil }
                    let url = FileManager.default.temporaryDirectory.appending(
                        path: "paseo-notif-\(abs(intent.id.hashValue)).\(thumbnail.fileExtension)")
                    try? data.write(to: url, options: .atomic)
                    return url
                }).value,
                let attachment = try? UNNotificationAttachment(
                    identifier: "paseo.thumbnail", url: fileURL)
            {
                content.attachments = [attachment]
            }
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// What the notification may show a thumbnail for: a permission request about
    /// an image (edit/read of a local image path, fetch of a remote image URL).
    /// Anything else has no honest image.
    private func thumbnailSource(for intent: AttentionIntent) ->
        (remoteURL: String?, daemonPath: String?, workspaceID: String?, fileExtension: String)?
    {
        guard let agentId = intent.target.agentId,
            let (request, _) = permissionRequestProvider?(agentId),
            let detail = request.detail
        else { return nil }
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp"]
        func imageExtension(ofPath path: String) -> String? {
            let ext = (path as NSString).pathExtension.lowercased()
            return imageExtensions.contains(ext) ? ext : nil
        }
        switch detail {
        case .edit(let path, _, _, _), .read(let path, _), .write(let path, _):
            guard let ext = imageExtension(ofPath: path),
                let workspaceID = intent.target.workspaceId
            else { return nil }
            return (nil, path, workspaceID, ext)
        case .fetch(let urlString, _, _):
            guard let url = URL(string: urlString),
                imageExtensions.contains(url.pathExtension.lowercased())
            else { return nil }
            return (urlString, nil, nil, url.pathExtension.lowercased())
        default:
            return nil
        }
    }

    static let requestIdKey = "paseo.permission.requestId"
    static let agentIdKey = "paseo.permission.agentId"
    static let hostKey = "paseo.permission.hostServerID"
    static let allowIdKey = "paseo.permission.allowActionId"
    static let denyIdKey = "paseo.permission.denyActionId"

    /// The "Open" fallback (G19): when a notification answer cannot be sent
    /// (nothing pending, reconnect failed), deep-link the agent so the reader
    /// sees the state instead of nothing.
    func postOpenFallback(agentId: String, hostServerID: String) {
        let content = UNMutableNotificationContent()
        content.title = "Review in Paseo"
        content.body = "Open the agent to answer."
        content.sound = .default
        content.threadIdentifier = "paseo.attention"
        content.userInfo = AttentionTarget.agent(agentId, workspaceId: nil).userInfo
        let request = UNNotificationRequest(
            identifier: "paseo.permission-fallback.\(agentId)", content: content,
            trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    /// Answers one notification response. With `.authenticationRequired` and no
    /// `.foreground` option the system handles the action without opening the
    /// app — the scene may be backgrounded or gone — so the send cannot depend
    /// on any SwiftUI view: hold a background task, await the handler, and only
    /// then complete. Expiry posts the Open fallback instead of losing the tap.
    private func handleResponse(_ response: UNNotificationResponse, completion: @escaping () -> Void) async {
        guard response.actionIdentifier == Self.allowActionID
            || response.actionIdentifier == Self.denyActionID
        else {
            var info: [String: String] = [:]
            for (key, value) in response.notification.request.content.userInfo {
                guard let key = key as? String, let value = value as? String else { continue }
                info[key] = value
            }
            if let target = AttentionTarget(userInfo: info) {
                pendingTarget = target
            }
            completion()
            return
        }
        var info: [String: String] = [:]
        for (key, value) in response.notification.request.content.userInfo {
            guard let key = key as? String, let value = value as? String else { continue }
            info[key] = value
        }
        guard let action = PendingPermissionAction(response: response, userInfo: info) else {
            completion()
            return
        }
        permissionTask = UIApplication.shared.beginBackgroundTask(withName: "paseo.permission-response") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.postOpenFallback(agentId: action.agentId, hostServerID: action.hostServerID)
                self.endPermissionTask()
            }
        }
        let confirmed = await performPermissionAction?(action) ?? false
        if !confirmed {
            postOpenFallback(agentId: action.agentId, hostServerID: action.hostServerID)
        }
        completion()
        endPermissionTask()
    }

    private func endPermissionTask() {
        guard permissionTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(permissionTask)
        permissionTask = .invalid
    }
}

/// The UNUserNotificationCenter delegate must be an NSObject. It carries no state beyond the
/// callbacks the coordinator installs once before any callback can run.
private final class NotificationDelegateProxy: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    /// The raw response plus its completion, for the coordinator to answer
    /// (possibly after async work) and complete exactly once.
    var onResponse:
        (@Sendable (UNNotificationResponse, @escaping () -> Void) -> Void)?

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
        let content = response.notification.request.content
        var info: [String: String] = [:]
        for (key, value) in content.userInfo {
            guard let key = key as? String, let value = value as? String else { continue }
            info[key] = value
        }
        // The coordinator answers (possibly after async work) and completes
        // exactly once; without a handler this falls through to the tap path.
        guard let onResponse else {
            let target = AttentionTarget(userInfo: info)
            completionHandler()
            guard let target else { return }
            onTap?(target)
            return
        }
        onResponse(response, completionHandler)
    }
}

private extension PendingPermissionAction {
    /// The tapped action plus the daemon action id it answers with. Nil unless every
    /// piece survived the userInfo round-trip.
    init?(response: UNNotificationResponse, userInfo: [String: String]) {
        let actionId = response.actionIdentifier
        let allow: Bool
        let daemonKey: String
        if actionId == NotificationCoordinator.allowActionID {
            allow = true
            daemonKey = NotificationCoordinator.allowIdKey
        } else if actionId == NotificationCoordinator.denyActionID {
            allow = false
            daemonKey = NotificationCoordinator.denyIdKey
        } else {
            return nil
        }
        guard let requestId = userInfo[NotificationCoordinator.requestIdKey],
            !requestId.isEmpty,
            let agentId = userInfo[NotificationCoordinator.agentIdKey],
            !agentId.isEmpty,
            let hostServerID = userInfo[NotificationCoordinator.hostKey],
            !hostServerID.isEmpty,
            let daemonActionId = userInfo[daemonKey],
            !daemonActionId.isEmpty
        else { return nil }
        self.init(
            requestId: requestId, agentId: agentId, hostServerID: hostServerID, allow: allow,
            daemonActionId: daemonActionId)
    }
}
