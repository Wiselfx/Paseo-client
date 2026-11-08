import Foundation

// Projects, the workspace directory, workspace creation and the GitHub clone flow.
//
// Source: messages.ts `WorkspaceDescriptorPayloadSchema`, `WorkspaceProjectDescriptorPayloadSchema`,
// `WorkspaceUpdateMessageSchema`, `ProjectUpdateMessageSchema`, `FetchWorkspacesRequestMessageSchema`,
// `ProjectListRequestMessageSchema`, `ProjectAddRequestSchema`, `ProjectRemoveRequestSchema`,
// `WorkspaceCreateRequestSchema`, `ArchiveWorkspaceRequestSchema`, `WorkspaceTitleSetRequestSchema`,
// `WorkspaceGithubSearchRepositoriesRequestSchema`, `ProjectGithubCloneRequestSchema`.
//
// Forward compatibility: every enum keeps unknown wire values, every optional field is optional
// here, and a newer daemon adding fields never fails a decode.

public enum WorkspaceStatusBucket: Sendable, Hashable, Decodable {
    case needsInput, failed, running, attention, done
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "needs_input": self = .needsInput
        case "failed": self = .failed
        case "running": self = .running
        case "attention": self = .attention
        case "done": self = .done
        case let other: self = .unknown(other)
        }
    }
}

public enum WorkspaceKind: Sendable, Hashable, Decodable {
    case directory, localCheckout, checkout, worktree
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "directory": self = .directory
        case "local_checkout": self = .localCheckout
        case "checkout": self = .checkout
        case "worktree": self = .worktree
        case let other: self = .unknown(other)
        }
    }
}

public enum WorkspaceProjectKind: Sendable, Hashable, Decodable {
    case git, nonGit, directory
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "git": self = .git
        case "non_git": self = .nonGit
        case "directory": self = .directory
        case let other: self = .unknown(other)
        }
    }
}

public enum WorkspaceSetupStatus: Sendable, Hashable, Decodable {
    case running, completed, failed, blocked
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "running": self = .running
        case "completed": self = .completed
        case "failed": self = .failed
        case "blocked": self = .blocked
        case let other: self = .unknown(other)
        }
    }
}

public struct WorkspaceDiffStat: Sendable, Hashable, Decodable {
    public var additions: Int
    public var deletions: Int
    public init(additions: Int, deletions: Int) {
        self.additions = additions
        self.deletions = deletions
    }
}

public enum WorkspaceScriptLifecycle: Sendable, Hashable, Decodable {
    case running, stopped
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "running": self = .running
        case "stopped": self = .stopped
        case let other: self = .unknown(other)
        }
    }
}

public enum WorkspaceScriptHealth: Sendable, Hashable, Decodable {
    case healthy, unhealthy
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "healthy": self = .healthy
        case "unhealthy": self = .unhealthy
        case let other: self = .unknown(other)
        }
    }
}

/// Source: messages.ts `WorkspaceScriptPayloadSchema`.
public struct WorkspaceScript: Sendable, Hashable, Decodable {
    public var scriptName: String
    /// `script` or `service`. Open on the wire; unknown values are kept.
    public var type: String?
    public var hostname: String?
    public var port: Int?
    public var localProxyUrl: String?
    public var publicProxyUrl: String?
    public var proxyUrl: String?
    public var lifecycle: WorkspaceScriptLifecycle?
    public var health: WorkspaceScriptHealth?
    public var exitCode: Int?
    public var terminalId: String?
}

/// Source: messages.ts `WorkspaceGitRuntimePayloadSchema`.
public struct WorkspaceGitRuntime: Sendable, Hashable, Decodable {
    public var currentBranch: String?
    public var remoteUrl: String?
    public var isPaseoOwnedWorktree: Bool?
    public var isDirty: Bool?
    public var aheadBehind: CheckoutAheadBehind?
    public var aheadOfOrigin: Int?
    public var behindOfOrigin: Int?

    public init(
        currentBranch: String? = nil,
        remoteUrl: String? = nil,
        isPaseoOwnedWorktree: Bool? = nil,
        isDirty: Bool? = nil,
        aheadBehind: CheckoutAheadBehind? = nil,
        aheadOfOrigin: Int? = nil,
        behindOfOrigin: Int? = nil
    ) {
        self.currentBranch = currentBranch
        self.remoteUrl = remoteUrl
        self.isPaseoOwnedWorktree = isPaseoOwnedWorktree
        self.isDirty = isDirty
        self.aheadBehind = aheadBehind
        self.aheadOfOrigin = aheadOfOrigin
        self.behindOfOrigin = behindOfOrigin
    }
}

/// The forge summary embedded in a workspace row. Source: messages.ts
/// `WorkspaceGitHubRuntimePayloadSchema` (legacy name; the field is forge-neutral).
public struct WorkspaceGitHubRuntime: Sendable, Hashable, Decodable {
    public var featuresEnabled: Bool?
    public var pullRequest: WorkspacePullRequest?
    public var error: WorkspaceRuntimeError?
    public var refreshedAt: String?

    public struct WorkspaceRuntimeError: Sendable, Hashable, Decodable {
        public var message: String
    }

    /// A PR/MR summary as the directory carries it. Source: the `pullRequest` object in
    /// `WorkspaceGitHubRuntimePayloadSchema`.
    public struct WorkspacePullRequest: Sendable, Hashable, Decodable {
        public var number: Int?
        public var url: String
        public var title: String
        public var state: String
        public var baseRefName: String
        public var headRefName: String
        public var isMerged: Bool
        public var isDraft: Bool?
        public var mergeable: String?
        public var checksStatus: String?
        public var reviewDecision: String?
        public var repoOwner: String?
        public var repoName: String?
        /// Open facts envelope; kept raw so a newer forge shape still decodes.
        public var github: JSONValue?
    }
}

/// One row of the sidebar. Source: messages.ts `WorkspaceDescriptorPayloadSchema`.
public struct WorkspaceDescriptor: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var projectId: String
    public var projectDisplayName: String
    public var projectCustomName: String?
    public var projectCustomIconRevision: String?
    public var projectRootPath: String
    public var workspaceDirectory: String?
    public var setupStatus: WorkspaceSetupStatus?
    /// Basename of the Paseo-owned worktree root, when there is one.
    public var worktreeSlug: String?
    public var projectKind: WorkspaceProjectKind
    public var workspaceKind: WorkspaceKind
    public var name: String
    /// The raw user override; `name` already carries the resolved value.
    public var title: String?
    public var pinnedAt: String?
    public var labels: [String]?
    public var background: Bool?
    public var archivingAt: String?
    public var status: WorkspaceStatusBucket
    public var statusEnteredAt: String?
    public var activityAt: String?
    public var createdAt: String?
    public var lastUserMessageAt: String?
    public var diffStat: WorkspaceDiffStat?
    public var scripts: [WorkspaceScript]
    public var gitRuntime: WorkspaceGitRuntime?
    public var githubRuntime: WorkspaceGitHubRuntime?
    public var forge: String?
    public var project: ProjectPlacement?
    public var syncSeq: Int?
    public var parentWorkspaceId: String?

    private enum K: String, CodingKey { case scripts }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        // `scripts` is defaulted on the wire but old daemons may omit it entirely.
        scripts = try c.decodeIfPresent([WorkspaceScript].self, forKey: .scripts) ?? []
        // The rest of the fields use the synthesized keys below.
        let all = try decoder.container(keyedBy: AllKeys.self)
        id = try all.decode(String.self, forKey: .id)
        projectId = try all.decode(String.self, forKey: .projectId)
        projectDisplayName = try all.decode(String.self, forKey: .projectDisplayName)
        projectCustomName = try all.decodeIfPresent(String.self, forKey: .projectCustomName)
        projectCustomIconRevision = try all.decodeIfPresent(String.self, forKey: .projectCustomIconRevision)
        projectRootPath = try all.decode(String.self, forKey: .projectRootPath)
        workspaceDirectory = try all.decodeIfPresent(String.self, forKey: .workspaceDirectory)
        setupStatus = try all.decodeIfPresent(WorkspaceSetupStatus.self, forKey: .setupStatus)
        worktreeSlug = try all.decodeIfPresent(String.self, forKey: .worktreeSlug)
        projectKind = try all.decode(WorkspaceProjectKind.self, forKey: .projectKind)
        workspaceKind = try all.decode(WorkspaceKind.self, forKey: .workspaceKind)
        name = try all.decode(String.self, forKey: .name)
        title = try all.decodeIfPresent(String.self, forKey: .title)
        pinnedAt = try all.decodeIfPresent(String.self, forKey: .pinnedAt)
        labels = try all.decodeIfPresent([String].self, forKey: .labels)
        background = try all.decodeIfPresent(Bool.self, forKey: .background)
        archivingAt = try all.decodeIfPresent(String.self, forKey: .archivingAt)
        status = try all.decode(WorkspaceStatusBucket.self, forKey: .status)
        statusEnteredAt = try all.decodeIfPresent(String.self, forKey: .statusEnteredAt)
        activityAt = try all.decodeIfPresent(String.self, forKey: .activityAt)
        createdAt = try all.decodeIfPresent(String.self, forKey: .createdAt)
        lastUserMessageAt = try all.decodeIfPresent(String.self, forKey: .lastUserMessageAt)
        diffStat = try all.decodeIfPresent(WorkspaceDiffStat.self, forKey: .diffStat)
        gitRuntime = try all.decodeIfPresent(WorkspaceGitRuntime.self, forKey: .gitRuntime)
        githubRuntime = try all.decodeIfPresent(WorkspaceGitHubRuntime.self, forKey: .githubRuntime)
        forge = try all.decodeIfPresent(String.self, forKey: .forge)
        project = try all.decodeIfPresent(ProjectPlacement.self, forKey: .project)
        syncSeq = try all.decodeIfPresent(Int.self, forKey: .syncSeq)
        parentWorkspaceId = try all.decodeIfPresent(String.self, forKey: .parentWorkspaceId)
    }

    private enum AllKeys: String, CodingKey {
        case id, projectId, projectDisplayName, projectCustomName, projectCustomIconRevision
        case projectRootPath, workspaceDirectory, setupStatus, worktreeSlug, projectKind, workspaceKind
        case name, title, pinnedAt, labels, background, archivingAt, status, statusEnteredAt
        case activityAt, createdAt, lastUserMessageAt, diffStat, gitRuntime, githubRuntime, forge
        case project, syncSeq, parentWorkspaceId
    }

    /// The directory RPCs and file reads use this as the workspace root.
    public var cwd: String { workspaceDirectory ?? projectRootPath }
    public var branch: String? { gitRuntime?.currentBranch }
    public var isDirty: Bool { gitRuntime?.isDirty == true }
    public var isPinned: Bool { pinnedAt != nil }
}

/// A project row, including parents whose last workspace was archived. Source: messages.ts
/// `WorkspaceProjectDescriptorPayloadSchema`.
public struct WorkspaceProjectDescriptor: Sendable, Hashable, Decodable, Identifiable {
    public var projectId: String
    public var projectKey: String?
    public var projectDisplayName: String
    public var projectCustomName: String?
    public var projectCustomIconRevision: String?
    public var projectIconRevision: String?
    public var projectRootPath: String
    public var projectKind: WorkspaceProjectKind
    public var syncSeq: Int?

    public var id: String { projectId }

    public init(
        projectId: String,
        projectKey: String? = nil,
        projectDisplayName: String,
        projectCustomName: String? = nil,
        projectCustomIconRevision: String? = nil,
        projectIconRevision: String? = nil,
        projectRootPath: String,
        projectKind: WorkspaceProjectKind,
        syncSeq: Int? = nil
    ) {
        self.projectId = projectId
        self.projectKey = projectKey
        self.projectDisplayName = projectDisplayName
        self.projectCustomName = projectCustomName
        self.projectCustomIconRevision = projectCustomIconRevision
        self.projectIconRevision = projectIconRevision
        self.projectRootPath = projectRootPath
        self.projectKind = projectKind
        self.syncSeq = syncSeq
    }
}

/// Live directory change. Source: messages.ts `WorkspaceUpdateMessageSchema`.
public enum WorkspaceUpdate: Sendable, Decodable {
    case upsert(WorkspaceDescriptor, seq: Int?)
    case remove(id: String, emptyProject: WorkspaceProjectDescriptor?, removedProjectId: String?, seq: Int?)
    case unknown(kind: String)

    private enum K: String, CodingKey { case kind, workspace, id, emptyProject, removedProjectId, seq }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "upsert":
            self = .upsert(
                try c.decode(WorkspaceDescriptor.self, forKey: .workspace),
                seq: try c.decodeIfPresent(Int.self, forKey: .seq))
        case "remove":
            self = .remove(
                id: try c.decode(String.self, forKey: .id),
                emptyProject: try c.decodeIfPresent(WorkspaceProjectDescriptor.self, forKey: .emptyProject),
                removedProjectId: try c.decodeIfPresent(String.self, forKey: .removedProjectId),
                seq: try c.decodeIfPresent(Int.self, forKey: .seq))
        case let other:
            self = .unknown(kind: other)
        }
    }
}

/// Live project change. Source: messages.ts `ProjectUpdateMessageSchema`.
public enum ProjectUpdate: Sendable, Decodable {
    case upsert(WorkspaceProjectDescriptor, seq: Int?)
    case remove(projectId: String, seq: Int?)
    case unknown(kind: String)

    private enum K: String, CodingKey { case kind, project, projectId, seq }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "upsert":
            self = .upsert(
                try c.decode(WorkspaceProjectDescriptor.self, forKey: .project),
                seq: try c.decodeIfPresent(Int.self, forKey: .seq))
        case "remove":
            self = .remove(
                projectId: try c.decode(String.self, forKey: .projectId),
                seq: try c.decodeIfPresent(Int.self, forKey: .seq))
        case let other:
            self = .unknown(kind: other)
        }
    }
}

/// Source: messages.ts `FetchWorkspacesRequestMessageSchema`.
public struct FetchWorkspacesRequest: PaseoRequest {
    public static let type = "fetch_workspaces_request"
    public static let responseType = "fetch_workspaces_response"

    public var requestId = ""
    public var includeBackground: Bool?
    public var filter: Filter?
    public var sort: [Sort]?
    public var page: Page?
    public var subscribe: Subscribe?

    public init(
        includeBackground: Bool? = nil,
        filter: Filter? = nil,
        sort: [Sort]? = nil,
        page: Page? = nil,
        subscribe: Bool = false
    ) {
        self.includeBackground = includeBackground
        self.filter = filter
        self.sort = sort
        self.page = page
        self.subscribe = subscribe ? Subscribe() : nil
    }

    public struct Subscribe: Encodable, Sendable {
        public init() {}
    }

    public struct Filter: Encodable, Sendable {
        public var query: String?
        public var projectId: String?
        public init(query: String? = nil, projectId: String? = nil) {
            self.query = query
            self.projectId = projectId
        }
    }

    /// `direction` is required per entry; this is an array of objects, not a bare enum.
    public struct Sort: Encodable, Sendable {
        public enum Key: String, Encodable, Sendable {
            case statusPriority = "status_priority"
            case activityAt = "activity_at"
            case name
            case projectId = "project_id"
        }
        public enum Direction: String, Encodable, Sendable { case asc, desc }
        public var key: Key
        public var direction: Direction
        public init(key: Key, direction: Direction) {
            self.key = key
            self.direction = direction
        }
    }

    public struct Page: Encodable, Sendable {
        public var limit: Int
        public var cursor: String?
        public init(limit: Int, cursor: String? = nil) {
            self.limit = limit
            self.cursor = cursor
        }
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var subscriptionId: String?
        public var entries: [WorkspaceDescriptor]
        public var emptyProjects: [WorkspaceProjectDescriptor]
        public var pageInfo: PageInfo

        public struct PageInfo: Decodable, Sendable, Hashable {
            public var nextCursor: String?
            public var prevCursor: String?
            public var hasMore: Bool
            public init(nextCursor: String? = nil, prevCursor: String? = nil, hasMore: Bool = false) {
                self.nextCursor = nextCursor
                self.prevCursor = prevCursor
                self.hasMore = hasMore
            }
        }

        private enum K: String, CodingKey { case requestId, subscriptionId, entries, emptyProjects, pageInfo }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decode(String.self, forKey: .requestId)
            subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId)
            entries = try c.decode([WorkspaceDescriptor].self, forKey: .entries)
            emptyProjects = try c.decodeIfPresent([WorkspaceProjectDescriptor].self, forKey: .emptyProjects) ?? []
            pageInfo =
                try c.decodeIfPresent(PageInfo.self, forKey: .pageInfo)
                ?? PageInfo()
        }
    }
}

/// Explicit event subscription, used for `project.update` and `checkout_status_update`.
/// Source: messages.ts `SessionEventsSetSubscriptionRequestSchema`,
/// `SessionEventsSetSubscriptionResponseSchema`.
public struct SessionEventsSetSubscriptionRequest: PaseoRequest {
    public static let type = "session.events.set_subscription.request"
    public static let responseType = "session.events.set_subscription.response"
    public var requestId = ""
    public var events: [String]
    public var notifications: Bool?

    public init(events: [String], notifications: Bool? = nil) {
        self.events = events
        self.notifications = notifications
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var subscriptionId: String?

        public init(requestId: String, subscriptionId: String?) {
            self.requestId = requestId
            self.subscriptionId = subscriptionId
        }
    }
}

/// Source: messages.ts `ProjectListRequestMessageSchema`.
public struct ProjectListRequest: PaseoRequest {
    public static let type = "project.list.request"
    public static let responseType = "project.list.response"
    public var requestId = ""
    public init() {}

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var projects: [WorkspaceProjectDescriptor]
    }
}

/// Source: messages.ts `ProjectAddRequestSchema`, `ProjectAddResponseSchema`.
public struct ProjectAddRequest: PaseoRequest {
    public static let type = "project.add.request"
    public static let responseType = "project.add.response"
    public var requestId = ""
    public var cwd: String
    public init(cwd: String) { self.cwd = cwd }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var project: WorkspaceProjectDescriptor?
        public var error: String?
        /// `directory_not_found`; open on the wire so newer codes still decode.
        public var errorCode: String?
    }
}

/// Source: messages.ts `ProjectRemoveRequestSchema`, `ProjectRemoveResponseSchema`.
public struct ProjectRemoveRequest: PaseoRequest {
    public static let type = "project.remove.request"
    public static let responseType = "project.remove.response"
    public var requestId = ""
    public var projectId: String
    public init(projectId: String) { self.projectId = projectId }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var projectId: String
        public var accepted: Bool
        public var removedWorkspaceIds: [String]
        public var error: String?

        private enum K: String, CodingKey { case requestId, projectId, accepted, removedWorkspaceIds, error }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decode(String.self, forKey: .requestId)
            projectId = try c.decode(String.self, forKey: .projectId)
            accepted = try c.decode(Bool.self, forKey: .accepted)
            removedWorkspaceIds = try c.decodeIfPresent([String].self, forKey: .removedWorkspaceIds) ?? []
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }

        public init(
            requestId: String, projectId: String, accepted: Bool, removedWorkspaceIds: [String],
            error: String?
        ) {
            self.requestId = requestId
            self.projectId = projectId
            self.accepted = accepted
            self.removedWorkspaceIds = removedWorkspaceIds
            self.error = error
        }
    }
}

/// Source: messages.ts `WorkspaceTitleSetRequestSchema`, `WorkspaceTitleSetResponseSchema`.
public struct WorkspaceTitleSetRequest: PaseoRequest {
    public static let type = "workspace.title.set.request"
    public static let responseType = "workspace.title.set.response"
    public var requestId = ""
    public var workspaceId: String
    /// Null or empty clears the override.
    public var title: String?
    public init(workspaceId: String, title: String?) {
        self.workspaceId = workspaceId
        self.title = title
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var workspaceId: String
        public var accepted: Bool
        public var title: String?
        public var error: String?

        public init(
            requestId: String, workspaceId: String, accepted: Bool, title: String?, error: String?
        ) {
            self.requestId = requestId
            self.workspaceId = workspaceId
            self.accepted = accepted
            self.title = title
            self.error = error
        }
    }
}

/// Source: messages.ts `ArchiveWorkspaceRequestSchema`, `ArchiveWorkspaceResponseMessageSchema`.
public struct ArchiveWorkspaceRequest: PaseoRequest {
    public static let type = "archive_workspace_request"
    public static let responseType = "archive_workspace_response"
    public var requestId = ""
    public var workspaceId: String
    public init(workspaceId: String) { self.workspaceId = workspaceId }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var workspaceId: String
        public var archivedAt: String?
        public var error: String?
        /// An undo stopped the archive before it finished.
        public var canceled: Bool?

        public init(
            requestId: String, workspaceId: String, archivedAt: String?, error: String?, canceled: Bool?
        ) {
            self.requestId = requestId
            self.workspaceId = workspaceId
            self.archivedAt = archivedAt
            self.error = error
            self.canceled = canceled
        }
    }
}

public enum WorkspaceWorktreeAction: String, Sendable, Encodable {
    case branchOff = "branch-off"
    case checkout
}

/// Source: messages.ts `ChangeRequestCheckoutSourceSchema`.
public struct ChangeRequestCheckoutSource: Sendable, Encodable, Hashable {
    public var kind = "change_request"
    public var forge: String?
    public var number: Int
    public var projectPath: String?
    public init(forge: String? = nil, number: Int, projectPath: String? = nil) {
        self.forge = forge
        self.number = number
        self.projectPath = projectPath
    }
}

/// The `source` discriminated union of `WorkspaceCreateRequestSchema`. Source: messages.ts
/// `WorkspaceCreateRequestSchema`.
public enum WorkspaceSource: Sendable, Encodable {
    case directory(path: String, projectId: String?)
    case worktree(Worktree)

    public struct Worktree: Sendable, Encodable, Hashable {
        public var cwd: String?
        public var projectId: String?
        public var action: WorkspaceWorktreeAction?
        /// Target branch for checkout, or base ref for branch-off.
        public var refName: String?
        public var baseBranch: String?
        public var branchName: String?
        public var checkoutSource: ChangeRequestCheckoutSource?
        /// COMPAT(githubPrNumber): retained for daemons older than `checkoutSource`.
        public var githubPrNumber: Int?
        public var worktreeSlug: String?

        public init(
            cwd: String? = nil,
            projectId: String? = nil,
            action: WorkspaceWorktreeAction? = nil,
            refName: String? = nil,
            baseBranch: String? = nil,
            branchName: String? = nil,
            checkoutSource: ChangeRequestCheckoutSource? = nil,
            githubPrNumber: Int? = nil,
            worktreeSlug: String? = nil
        ) {
            self.cwd = cwd
            self.projectId = projectId
            self.action = action
            self.refName = refName
            self.baseBranch = baseBranch
            self.branchName = branchName
            self.checkoutSource = checkoutSource
            self.githubPrNumber = githubPrNumber
            self.worktreeSlug = worktreeSlug
        }
    }

    private enum K: String, CodingKey {
        case kind, path, projectId, cwd, action, refName, baseBranch, branchName, checkoutSource
        case githubPrNumber, worktreeSlug
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .directory(let path, let projectId):
            try c.encode("directory", forKey: .kind)
            try c.encode(path, forKey: .path)
            try c.encodeIfPresent(projectId, forKey: .projectId)
        case .worktree(let worktree):
            try c.encode("worktree", forKey: .kind)
            try c.encodeIfPresent(worktree.cwd, forKey: .cwd)
            try c.encodeIfPresent(worktree.projectId, forKey: .projectId)
            try c.encodeIfPresent(worktree.action, forKey: .action)
            try c.encodeIfPresent(worktree.refName, forKey: .refName)
            try c.encodeIfPresent(worktree.baseBranch, forKey: .baseBranch)
            try c.encodeIfPresent(worktree.branchName, forKey: .branchName)
            try c.encodeIfPresent(worktree.checkoutSource, forKey: .checkoutSource)
            try c.encodeIfPresent(worktree.githubPrNumber, forKey: .githubPrNumber)
            try c.encodeIfPresent(worktree.worktreeSlug, forKey: .worktreeSlug)
        }
    }
}

/// Source: messages.ts `WorkspaceCreateRequestSchema`, `WorkspaceCreateResponseSchema`.
public struct WorkspaceCreateRequest: PaseoRequest {
    public static let type = "workspace.create.request"
    public static let responseType = "workspace.create.response"
    public var requestId = ""
    public var workspaceId: String?
    public var idempotencyKey: String?
    public var title: String?
    public var background: Bool?
    public var source: WorkspaceSource

    public init(
        source: WorkspaceSource,
        title: String? = nil,
        idempotencyKey: String? = nil,
        workspaceId: String? = nil,
        background: Bool? = nil
    ) {
        self.source = source
        self.title = title
        self.idempotencyKey = idempotencyKey
        self.workspaceId = workspaceId
        self.background = background
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var workspace: WorkspaceDescriptor?
        public var setupTerminalId: String?
        public var setupSkippedReason: String?
        public var error: String?
        public var errorCode: String?
    }
}

public enum GithubRepositoryVisibility: Sendable, Hashable, Decodable {
    case `public`, `private`, `internal`
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "public": self = .public
        case "private": self = .private
        case "internal": self = .internal
        case let other: self = .unknown(other)
        }
    }
}

/// Source: messages.ts `GithubRepositorySchema`.
public struct GithubRepository: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var name: String
    public var nameWithOwner: String
    public var description: String?
    public var visibility: GithubRepositoryVisibility
    public var updatedAt: String
    public var cloneUrl: String
}

/// Source: messages.ts `WorkspaceGithubSearchRepositoriesRequestSchema`.
public struct GithubRepositorySearchRequest: PaseoRequest {
    public static let type = "workspace.github.search_repositories.request"
    public static let responseType = "workspace.github.search_repositories.response"
    public var requestId = ""
    public var query: String
    public var limit: Int?
    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }

    public struct Response: Decodable, Sendable {
        public enum Status: Sendable, Hashable {
            case success, unavailable, unauthenticated, error
            case unknown(String)
        }

        public var status: Status
        public var repositories: [GithubRepository]
        public var available: Bool
        public var error: String?
        /// `gh_missing` on the `unavailable` branch.
        public var reason: String?

        private enum K: String, CodingKey { case status, repositories, available, error, reason }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            switch try c.decode(String.self, forKey: .status) {
            case "success": status = .success
            case "unavailable": status = .unavailable
            case "unauthenticated": status = .unauthenticated
            case "error": status = .error
            case let other: status = .unknown(other)
            }
            repositories = try c.decodeIfPresent([GithubRepository].self, forKey: .repositories) ?? []
            available = try c.decodeIfPresent(Bool.self, forKey: .available) ?? false
            error = try c.decodeIfPresent(String.self, forKey: .error)
            reason = try c.decodeIfPresent(String.self, forKey: .reason)
        }
    }
}

public enum GithubCloneProtocol: String, Sendable, Encodable {
    case https, ssh
}

/// Source: messages.ts `ProjectGithubCloneRequestSchema`, `ProjectGithubCloneResponseSchema`.
public struct ProjectGithubCloneRequest: PaseoRequest {
    public static let type = "project.github.clone.request"
    public static let responseType = "project.github.clone.response"
    public var requestId = ""
    public var repo: String
    public var cloneProtocol: GithubCloneProtocol?
    public var targetDirectory: String

    public init(repo: String, targetDirectory: String, cloneProtocol: GithubCloneProtocol? = nil) {
        self.repo = repo
        self.targetDirectory = targetDirectory
        self.cloneProtocol = cloneProtocol
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var repo: String
        public var checkoutPath: String?
        public var project: WorkspaceProjectDescriptor?
        public var error: String?

        public init(
            requestId: String, repo: String, checkoutPath: String?,
            project: WorkspaceProjectDescriptor?, error: String?
        ) {
            self.requestId = requestId
            self.repo = repo
            self.checkoutPath = checkoutPath
            self.project = project
            self.error = error
        }
    }
}
