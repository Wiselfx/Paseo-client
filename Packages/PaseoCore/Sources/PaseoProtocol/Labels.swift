import Foundation

// Workspace labels. Source: messages.ts `WorkspaceLabelColorSchema` (`WORKSPACE_LABEL_COLORS`),
// `WorkspaceLabelDefinitionSchema`, `WorkspaceLabelListRequestSchema` (`:1080`),
// `WorkspaceLabelAssignmentSetRequestSchema`, `WorkspaceLabelUpdateRequestSchema`,
// `WorkspaceLabelDeleteRequestSchema`, `WorkspaceLabelDeleteInspectRequestSchema`.
// Live updates: `workspace.label.update` with a `generation`/`seq` cursor (:4588-4627).
// Gate: `features.workspaceLabels` (added in v0.5.0).

// MARK: - Definition

/// One of the ten identity hues a label can take. Unknown names pass through so a newer
/// daemon's palette additions decode instead of break.
public struct WorkspaceLabelColor: Sendable, Hashable, Decodable, Encodable {
    public var rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public static let violet = WorkspaceLabelColor("violet")
    public static let sky = WorkspaceLabelColor("sky")
    public static let emerald = WorkspaceLabelColor("emerald")
    public static let orange = WorkspaceLabelColor("orange")
    public static let pink = WorkspaceLabelColor("pink")
    public static let indigo = WorkspaceLabelColor("indigo")
    public static let teal = WorkspaceLabelColor("teal")
    public static let red = WorkspaceLabelColor("red")
    public static let amber = WorkspaceLabelColor("amber")
    public static let blue = WorkspaceLabelColor("blue")

    /// The ten names the daemon currently knows, in its order. Use for pickers and swatches.
    public static let allKnown: [WorkspaceLabelColor] = [
        .violet, .sky, .emerald, .orange, .pink, .indigo, .teal, .red, .amber, .blue,
    ]

    public var isKnown: Bool { Self.allKnown.contains(self) }
}

/// Source: messages.ts `WorkspaceLabelDefinitionSchema`.
public struct WorkspaceLabelDefinition: Sendable, Hashable, Decodable, Encodable {
    public var name: String
    public var color: WorkspaceLabelColor

    public init(name: String, color: WorkspaceLabelColor) {
        self.name = name
        self.color = color
    }
}

// MARK: - List

/// Source: messages.ts `WorkspaceLabelListRequestSchema` (`workspace.label.list.request`).
/// `subscribe` registers the socket for `workspace.label.update` pushes; the response's `sync`
/// cursor catches the label catalog up to a `generation`/`headSeq` checkpoint.
public struct WorkspaceLabelListRequest: PaseoRequest {
    public static let type = "workspace.label.list.request"
    public static let responseType = "workspace.label.list.response"
    public var requestId = ""
    public var subscribe: Subscribe?
    public var sync: Sync?

    public init(subscribe: Subscribe? = nil, sync: Sync? = nil) {
        self.subscribe = subscribe
        self.sync = sync
    }

    public struct Subscribe: Encodable, Sendable {
        public var subscriptionId: String?
        public init(subscriptionId: String? = nil) { self.subscriptionId = subscriptionId }
    }

    public struct Sync: Encodable, Sendable {
        public var generation: String
        public var afterSeq: Int
        public init(generation: String, afterSeq: Int) {
            self.generation = generation
            self.afterSeq = afterSeq
        }
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var subscriptionId: String?
        public var labels: [WorkspaceLabelDefinition]
        public var sync: SyncMetadata
    }

    public struct SyncMetadata: Decodable, Sendable {
        public var generation: String
        public var headSeq: Int
        public var mode: Mode
        public var removals: [Removal]

        public enum Mode: Sendable, Hashable, Decodable {
            case snapshot
            case changes
            case unknown(String)

            public init(from decoder: Decoder) throws {
                switch try decoder.singleValueContainer().decode(String.self) {
                case "snapshot": self = .snapshot
                case "changes": self = .changes
                case let other: self = .unknown(other)
                }
            }
        }

        public struct Removal: Sendable, Hashable, Decodable {
            public var name: String
            public var seq: Int
        }
    }
}

// MARK: - Catalog updates (pushed)

/// Source: messages.ts `WorkspaceLabelUpdateSchema` (`workspace.label.update`).
public enum WorkspaceLabelUpdate: Sendable, Hashable, Decodable {
    case upsert(WorkspaceLabelDefinition, previousName: String?, generation: String, seq: Int)
    case remove(name: String, generation: String, seq: Int)
    /// A kind we don't know. The store resyncs from the catalog on this.
    case unknown(String, generation: String, seq: Int)

    private enum K: String, CodingKey {
        case kind, label, previousName, name, generation, seq
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let generation = try c.decode(String.self, forKey: .generation)
        let seq = try c.decode(Int.self, forKey: .seq)
        switch try c.decode(String.self, forKey: .kind) {
        case "upsert":
            let label = try c.decode(WorkspaceLabelDefinition.self, forKey: .label)
            let previousName = try c.decodeIfPresent(String.self, forKey: .previousName)
            self = .upsert(label, previousName: previousName, generation: generation, seq: seq)
        case "remove":
            let name = try c.decode(String.self, forKey: .name)
            self = .remove(name: name, generation: generation, seq: seq)
        case let other:
            self = .unknown(other, generation: generation, seq: seq)
        }
    }

    public var generation: String {
        switch self {
        case .upsert(_, _, let generation, _): generation
        case .remove(_, let generation, _): generation
        case .unknown(_, let generation, _): generation
        }
    }

    public var seq: Int {
        switch self {
        case .upsert(_, _, _, let seq): seq
        case .remove(_, _, let seq): seq
        case .unknown(_, _, let seq): seq
        }
    }
}

// MARK: - Assignment

/// Source: messages.ts `WorkspaceLabelAssignmentSetRequestSchema`
/// (`workspace.label.assignment.set.request`). Assigning an unknown label registers it in the
/// catalog — this is how a new label is created.
public struct WorkspaceLabelAssignmentSetRequest: PaseoRequest {
    public static let type = "workspace.label.assignment.set.request"
    public static let responseType = "workspace.label.assignment.set.response"
    public var requestId = ""
    public var workspaceId: String
    public var label: WorkspaceLabelDefinition
    public var assigned: Bool

    public init(workspaceId: String, label: WorkspaceLabelDefinition, assigned: Bool) {
        self.workspaceId = workspaceId
        self.label = label
        self.assigned = assigned
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var label: WorkspaceLabelDefinition
        public var workspaceLabels: [String]
    }
}

// MARK: - Edit & delete

/// Source: messages.ts `WorkspaceLabelUpdateRequestSchema` (`workspace.label.update.request`).
/// The server applies name and colour in one RPC; omitting a field leaves it alone.
public struct WorkspaceLabelUpdateRequest: PaseoRequest {
    public static let type = "workspace.label.update.request"
    public static let responseType = "workspace.label.update.response"
    public var requestId = ""
    public var name: String
    public var newName: String?
    public var color: WorkspaceLabelColor?

    public init(name: String, newName: String? = nil, color: WorkspaceLabelColor? = nil) {
        self.name = name
        self.newName = newName
        self.color = color
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var label: WorkspaceLabelDefinition
        public var affectedWorkspaceCount: Int
    }
}

/// Source: messages.ts `WorkspaceLabelDeleteRequestSchema` (`workspace.label.delete.request`).
public struct WorkspaceLabelDeleteRequest: PaseoRequest {
    public static let type = "workspace.label.delete.request"
    public static let responseType = "workspace.label.delete.response"
    public var requestId = ""
    public var name: String

    public init(name: String) { self.name = name }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var affectedWorkspaceCount: Int
    }
}

/// Source: messages.ts `WorkspaceLabelDeleteInspectRequestSchema`
/// (`workspace.label.delete.inspect.request`). Read-only count of workspaces the delete would hit.
public struct WorkspaceLabelDeleteInspectRequest: PaseoRequest {
    public static let type = "workspace.label.delete.inspect.request"
    public static let responseType = "workspace.label.delete.inspect.response"
    public var requestId = ""
    public var name: String

    public init(name: String) { self.name = name }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var affectedWorkspaceCount: Int
    }
}
