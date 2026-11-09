import Foundation

// Project rename, workspace pin, workspace base branch, and workspace archive undo.
//
// Source: messages.ts `ProjectRenameRequestSchema`, `WorkspacePinSetRequestSchema`,
// `WorkspaceBaseBranchSetRequestSchema`, `WorkspaceArchiveUndoRequestSchema` and their response
// schemas. Capability gates: `features.workspacePinning` (added in v0.1.107),
// `features.workspaceBaseBranch` (added after v0.11.2), `features.workspaceArchiveUndo`
// (added in v0.15.3).
//
// Forward compatibility: every field that may be absent decodes optionally; a newer daemon adding
// fields cannot make a decode fail.

/// Source: messages.ts `ProjectRenameRequestSchema`, `ProjectRenameResponsePayloadSchema`.
public struct ProjectRenameRequest: PaseoRequest {
    public static let type = "project.rename.request"
    public static let responseType = "project.rename.response"
    public var requestId = ""
    public var projectId: String
    /// Null clears the override (the daemon reverts to the derived name).
    public var customName: String?

    public init(projectId: String, customName: String?) {
        self.projectId = projectId
        self.customName = customName
    }

    private enum CodingKeys: String, CodingKey { case requestId, projectId, customName }

    // `customName: null` is required on the wire to clear the override; a plain synthesized
    // encoder would omit the key and the daemon rejects the frame.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(projectId, forKey: .projectId)
        try c.encode(customName, forKey: .customName)
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var projectId: String
        public var accepted: Bool
        public var customName: String?
        public var error: String?

        public init(
            requestId: String, projectId: String, accepted: Bool, customName: String?,
            error: String?
        ) {
            self.requestId = requestId
            self.projectId = projectId
            self.accepted = accepted
            self.customName = customName
            self.error = error
        }
    }
}

/// Source: messages.ts `WorkspacePinSetRequestSchema`, `WorkspacePinSetResponsePayloadSchema`.
public struct WorkspacePinSetRequest: PaseoRequest {
    public static let type = "workspace.pin.set.request"
    public static let responseType = "workspace.pin.set.response"
    public var requestId = ""
    public var workspaceId: String
    public var pinned: Bool

    public init(workspaceId: String, pinned: Bool) {
        self.pinned = pinned
        self.workspaceId = workspaceId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var workspaceId: String
        public var accepted: Bool
        public var pinnedAt: String?
        public var error: String?

        public init(
            requestId: String, workspaceId: String, accepted: Bool, pinnedAt: String?, error: String?
        ) {
            self.requestId = requestId
            self.workspaceId = workspaceId
            self.accepted = accepted
            self.pinnedAt = pinnedAt
            self.error = error
        }
    }
}

/// Source: messages.ts `WorkspaceBaseBranchSetRequestSchema`,
/// `WorkspaceBaseBranchSetResponseSchema` (`set_daemon_config_request` carries no revision;
/// this is unrelated to the daemon config RPC).
public struct WorkspaceBaseBranchSetRequest: PaseoRequest {
    public static let type = "workspace.base_branch.set.request"
    public static let responseType = "workspace.base_branch.set.response"
    public var requestId = ""
    public var workspaceId: String
    public var baseRef: String

    public init(workspaceId: String, baseRef: String) {
        self.baseRef = baseRef
        self.workspaceId = workspaceId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var workspaceId: String
        public var accepted: Bool
        public var baseRef: String?
        public var error: String?

        public init(
            requestId: String, workspaceId: String, accepted: Bool, baseRef: String?, error: String?
        ) {
            self.requestId = requestId
            self.workspaceId = workspaceId
            self.accepted = accepted
            self.baseRef = baseRef
            self.error = error
        }
    }
}

/// Undoes the latest archive of a workspace: cancels it if it is still running on the host,
/// otherwise restores the workspace, then unarchives the agents that archive took down.
/// Source: messages.ts `WorkspaceArchiveUndoRequestSchema`, `WorkspaceArchiveUndoResponseSchema`.
public struct WorkspaceArchiveUndoRequest: PaseoRequest {
    public static let type = "workspace.archive.undo.request"
    public static let responseType = "workspace.archive.undo.response"
    public var requestId = ""
    public var workspaceId: String

    public init(workspaceId: String) {
        self.workspaceId = workspaceId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var workspaceId: String
        public var accepted: Bool
        public var error: String?

        public init(requestId: String, workspaceId: String, accepted: Bool, error: String?) {
            self.requestId = requestId
            self.workspaceId = workspaceId
            self.accepted = accepted
            self.error = error
        }
    }
}
