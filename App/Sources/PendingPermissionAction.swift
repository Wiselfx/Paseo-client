import Foundation

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

extension PendingPermissionAction {
    /// The tapped action plus the daemon action id it answers with. Nil unless every
    /// piece survived the userInfo round-trip.
    init?(actionId: String, userInfo: [String: String]) {
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
