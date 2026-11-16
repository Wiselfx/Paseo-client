import Foundation

// Worktree setup observation: status/subscribe/run RPCs and the live progress push.
//
// Source: messages.ts `WorkspaceSetupSnapshotSchema`, `WorktreeSetupDetailPayloadSchema`,
// `WorktreeSetupCommandSnapshotSchema`, `WorkspaceSetupStatusResponseMessageSchema`,
// `WorkspaceSetupSubscribeResponseMessageSchema`, `WorkspaceSetupRunResponseMessageSchema`,
// `WorkspaceSetupProgressMessageSchema` (packages/protocol/src/messages.ts :4695-4765,
// :571-593). The capability gates are `server_info.features.workspaceSetupObservation`
// and `features.workspaceSetupRun`.
//
// `WorkspaceSetupStatus` is reused from Workspaces.swift (already used by the descriptor).
// Wire quirks handled here: the snapshot is nullable in both responses; `blockedSource` only
// appears when status is "blocked"; command `log` defaults to "" and `exitCode` is nullable.

/// Client capability names this client knows about but does NOT advertise in its hello. The
/// daemon only honors them on sockets that advertise them (`ClientCapabilities.implemented`
/// in Handshake.swift); advertising one without implementing it would enable daemon paths this
/// client cannot handle.
public enum SetupCapabilityNames {
    /// Modern owned subscriptions; required by the setup-subscribe path.
    public static let ownedSubscriptions = OwnedSubscriptions.capability
    /// Worktree setup observation (modern `workspace.setup.subscribe.request` companion).
    public static let workspaceSetupObservation = OwnedSubscriptions.setupObservationCapability
}

/// Per-command status. Source: messages.ts `WorktreeSetupCommandSnapshotSchema.status`.
public enum WorkspaceSetupCommandStatus: Sendable, Hashable, Decodable {
    case running, completed, failed
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "running": self = .running
        case "completed": self = .completed
        case "failed": self = .failed
        case let other: self = .unknown(other)
        }
    }
}

/// One setup command and its outcome. Source: messages.ts `WorktreeSetupCommandSnapshotSchema`.
public struct WorkspaceSetupCommand: Sendable, Hashable, Decodable, Identifiable {
    public var index: Int
    public var command: String
    public var cwd: String
    public var log: String
    public var status: WorkspaceSetupCommandStatus
    /// `null` while running; the shell's exit code once it settles.
    public var exitCode: Int?
    public var durationMs: Int?

    public var id: Int { index }

    public init(
        index: Int, command: String, cwd: String, log: String, status: WorkspaceSetupCommandStatus,
        exitCode: Int? = nil, durationMs: Int? = nil
    ) {
        self.index = index
        self.command = command
        self.cwd = cwd
        self.log = log
        self.status = status
        self.exitCode = exitCode
        self.durationMs = durationMs
    }

    private enum K: String, CodingKey {
        case index, command, cwd, log, status, exitCode, durationMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        log = try c.decodeIfPresent(String.self, forKey: .log) ?? ""
        status = (try? c.decode(WorkspaceSetupCommandStatus.self, forKey: .status)) ?? .unknown("")
        exitCode = try c.decodeIfPresent(Int.self, forKey: .exitCode)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
    }
}

/// The setup step the worktree is blocked on (e.g. an unmerged change request).
/// Source: messages.ts `WorkspaceSetupSnapshotSchema.blockedSource` /
/// `WorkspaceSetupProgressMessageSchema.blockedSource`.
public struct WorkspaceSetupBlockedSource: Sendable, Hashable, Decodable {
    /// `"change_request"` today; unknown values tolerated.
    public var kind: String
    public var forge: String
    public var number: Int
    public var headRepository: String

    public init(kind: String, forge: String, number: Int, headRepository: String) {
        self.kind = kind
        self.forge = forge
        self.number = number
        self.headRepository = headRepository
    }

    private enum K: String, CodingKey { case kind, forge, number, headRepository }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "change_request"
        forge = try c.decodeIfPresent(String.self, forKey: .forge) ?? ""
        number = try c.decodeIfPresent(Int.self, forKey: .number) ?? 0
        headRepository = try c.decodeIfPresent(String.self, forKey: .headRepository) ?? ""
    }
}

/// The detail of a worktree setup run: the log, per-command snapshots, and a path.
/// Source: messages.ts `WorktreeSetupDetailPayloadSchema`.
public struct WorkspaceSetupDetail: Sendable, Hashable, Decodable {
    /// The wire's discriminator is `"worktree_setup"`; tolerated as an opaque string.
    public var type: String
    public var worktreePath: String
    public var branchName: String
    public var log: String
    public var commands: [WorkspaceSetupCommand]
    public var truncated: Bool?

    public init(
        type: String, worktreePath: String, branchName: String, log: String,
        commands: [WorkspaceSetupCommand], truncated: Bool? = nil
    ) {
        self.type = type
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.log = log
        self.commands = commands
        self.truncated = truncated
    }

    private enum K: String, CodingKey {
        case type, worktreePath, branchName, log, commands, truncated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "worktree_setup"
        worktreePath = try c.decodeIfPresent(String.self, forKey: .worktreePath) ?? ""
        branchName = try c.decodeIfPresent(String.self, forKey: .branchName) ?? ""
        log = try c.decodeIfPresent(String.self, forKey: .log) ?? ""
        commands = try c.decodeIfPresent([WorkspaceSetupCommand].self, forKey: .commands) ?? []
        truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated)
    }
}

/// One snapshot of a workspace's setup state. Source: messages.ts `WorkspaceSetupSnapshotSchema`.
public struct WorkspaceSetupSnapshot: Sendable, Hashable, Decodable {
    public var status: WorkspaceSetupStatus
    public var detail: WorkspaceSetupDetail
    public var error: String?
    public var blockedSource: WorkspaceSetupBlockedSource?

    public init(
        status: WorkspaceSetupStatus, detail: WorkspaceSetupDetail, error: String? = nil,
        blockedSource: WorkspaceSetupBlockedSource? = nil
    ) {
        self.status = status
        self.detail = detail
        self.error = error
        self.blockedSource = blockedSource
    }

    private enum K: String, CodingKey { case status, detail, error, blockedSource }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        status = (try? c.decode(WorkspaceSetupStatus.self, forKey: .status)) ?? .unknown("")
        detail = try c.decode(WorkspaceSetupDetail.self, forKey: .detail)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        blockedSource = try c.decodeIfPresent(WorkspaceSetupBlockedSource.self, forKey: .blockedSource)
    }
}

/// A pushed `workspace_setup_progress` frame (session-wrapped on the wire).
/// Source: messages.ts `WorkspaceSetupProgressMessageSchema`.
public struct WorkspaceSetupProgress: Sendable, Hashable, Decodable {
    public var subscriptionId: String?
    public var workspaceId: String
    public var status: WorkspaceSetupStatus
    public var detail: WorkspaceSetupDetail
    public var error: String?
    public var blockedSource: WorkspaceSetupBlockedSource?

    public var snapshot: WorkspaceSetupSnapshot {
        WorkspaceSetupSnapshot(
            status: status, detail: detail, error: error, blockedSource: blockedSource)
    }

    private enum K: String, CodingKey {
        case subscriptionId, workspaceId, status, detail, error, blockedSource
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId)
        workspaceId = try c.decode(String.self, forKey: .workspaceId)
        status = (try? c.decode(WorkspaceSetupStatus.self, forKey: .status)) ?? .unknown("")
        detail = try c.decode(WorkspaceSetupDetail.self, forKey: .detail)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        blockedSource = try c.decodeIfPresent(WorkspaceSetupBlockedSource.self, forKey: .blockedSource)
    }
}

/// Source: messages.ts `WorkspaceSetupStatusRequestSchema`, `WorkspaceSetupStatusResponseMessageSchema`.
public struct WorkspaceSetupStatusRequest: PaseoRequest {
    public static let type = "workspace_setup_status_request"
    public static let responseType = "workspace_setup_status_response"
    public var requestId = ""
    public var workspaceId: String
    public init(workspaceId: String) { self.workspaceId = workspaceId }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var workspaceId: String
        /// Nullable: the daemon sends null when the workspace never had a setup run.
        public var snapshot: WorkspaceSetupSnapshot?

        private enum K: String, CodingKey { case requestId, workspaceId, snapshot }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId) ?? ""
            snapshot = try c.decodeIfPresent(WorkspaceSetupSnapshot.self, forKey: .snapshot)
        }
    }
}

/// Source: messages.ts `WorkspaceSetupSubscribeRequestSchema`,
/// `WorkspaceSetupSubscribeResponseMessageSchema`.
public struct WorkspaceSetupSubscribeRequest: PaseoRequest {
    public static let type = "workspace.setup.subscribe.request"
    public static let responseType = "workspace.setup.subscribe.response"
    public var requestId = ""
    public var workspaceId: String
    public init(workspaceId: String) { self.workspaceId = workspaceId }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        /// Present only when the daemon runs the modern owned-subscription path.
        public var subscriptionId: String?
        public var workspaceId: String
        /// Nullable: the daemon may not have a snapshot to replay yet.
        public var snapshot: WorkspaceSetupSnapshot?

        private enum K: String, CodingKey { case requestId, subscriptionId, workspaceId, snapshot }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId)
            workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId) ?? ""
            snapshot = try c.decodeIfPresent(WorkspaceSetupSnapshot.self, forKey: .snapshot)
        }
    }
}

/// Source: messages.ts `WorkspaceSetupRunRequestSchema`, `WorkspaceSetupRunResponseMessageSchema`.
public struct WorkspaceSetupRunRequest: PaseoRequest {
    public static let type = "workspace.setup.run.request"
    public static let responseType = "workspace.setup.run.response"
    public var requestId = ""
    public var workspaceId: String
    public init(workspaceId: String) { self.workspaceId = workspaceId }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var workspaceId: String
        /// Whether the daemon started the setup run.
        public var started: Bool
        public var error: String?

        private enum K: String, CodingKey { case requestId, workspaceId, started, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId) ?? ""
            started = try c.decodeIfPresent(Bool.self, forKey: .started) ?? false
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}
