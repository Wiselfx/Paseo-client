import Foundation
import UIKit
import Observation
import PaseoStore
import PaseoUI
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
    /// Answers a notification Allow/Deny: reconnects if needed and sends through
    /// the store's permission path. Set once at launch by the composition root
    /// (never by a view). Returns whether the daemon confirmed.
    var performPermissionAction: (@MainActor (PendingPermissionAction) async -> Bool)?
    /// Resolves an agent id to its latest permission request plus the daemon
    /// server id to answer on (or nil). Set once at launch by the composition
    /// root, which owns the session.
    var permissionRequestProvider: ((String) -> (AgentPermissionRequest, String)?)?

    private let proxy: NotificationDelegateProxy

    private static let promptedKey = "paseo.notifications.prompted"
    nonisolated static let permissionCategoryID = "paseo.permission"
    nonisolated static let allowActionID = "paseo.permission.allow"
    nonisolated static let denyActionID = "paseo.permission.deny"

    init() {
        let proxy = NotificationDelegateProxy()
        self.proxy = proxy
        proxy.onResponse = { [weak self] actionId, info, completion in
            Task { @MainActor [weak self] in
                guard let self else { completion(); return }
                await self.handleResponse(actionId: actionId, info: info, completion: completion)
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
                        let data = NotificationThumbnails.cachedData(
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

    nonisolated static let requestIdKey = "paseo.permission.requestId"
    nonisolated static let agentIdKey = "paseo.permission.agentId"
    nonisolated static let hostKey = "paseo.permission.hostServerID"
    nonisolated static let allowIdKey = "paseo.permission.allowActionId"
    nonisolated static let denyIdKey = "paseo.permission.denyActionId"

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
    /// Values only cross the hop from the delegate (the response object is not Sendable).
    private func handleResponse(
        actionId: String, info: [String: String], completion: @escaping @Sendable () -> Void
    ) async {
        guard actionId == Self.allowActionID || actionId == Self.denyActionID else {
            if let target = AttentionTarget(userInfo: info) {
                pendingTarget = target
            }
            completion()
            return
        }
        guard let action = PendingPermissionAction(actionId: actionId, userInfo: info) else {
            completion()
            return
        }
        // One box per answer: answers are reentrant (two quick Allow/Deny taps overlap
        // across the daemon wait), so a shared slot would end the wrong task and leak
        // the other.
        let box = BackgroundTaskBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: "paseo.permission-response") {
            [weak self] in
            Task { @MainActor [weak self] in
                self?.postOpenFallback(agentId: action.agentId, hostServerID: action.hostServerID)
                if box.id != .invalid {
                    UIApplication.shared.endBackgroundTask(box.id)
                    box.id = .invalid
                }
            }
        }
        defer {
            if box.id != .invalid {
                UIApplication.shared.endBackgroundTask(box.id)
                box.id = .invalid
            }
        }
        let confirmed = await performPermissionAction?(action) ?? false
        if !confirmed {
            postOpenFallback(agentId: action.agentId, hostServerID: action.hostServerID)
        }
        completion()
    }
}
