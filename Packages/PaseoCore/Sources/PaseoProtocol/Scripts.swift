import Foundation

// Workspace scripts: the `paseo.json` scripts panel and its RPCs.
//
// Source: packages/protocol/src/messages.ts `WorkspaceScriptPayloadSchema`,
// `WorkspaceScriptOperationPayloadSchema`, `WorkspaceScriptListRequestSchema`,
// `WorkspaceScriptStartRequestSchema`, `WorkspaceScriptStopRequestSchema` and
// `ScriptStatusUpdateMessageSchema`.

// Source: messages.ts `WorkspaceScriptPayloadSchema.type`, default `service`.
public enum WorkspaceScriptType: Sendable, Hashable {
    case script
    case service
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "script": self = .script
        case "service": self = .service
        case let other: self = .unknown(other)
        }
    }
}

// Source: messages.ts `WorkspaceScriptLifecycleSchema`.
public enum WorkspaceScriptLifecycle: Sendable, Hashable, Decodable {
    case running
    case stopped
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "running": self = .running
        case "stopped": self = .stopped
        case let other: self = .unknown(other)
        }
    }
}

// Source: messages.ts `WorkspaceScriptHealthSchema`.
public enum WorkspaceScriptHealth: Sendable, Hashable, Decodable {
    case healthy
    case unhealthy
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "healthy": self = .healthy
        case "unhealthy": self = .unhealthy
        case let other: self = .unknown(other)
        }
    }
}

// Source: messages.ts `WorkspaceScriptPayloadSchema`.
public struct WorkspaceScript: Sendable, Hashable, Decodable, Identifiable {
    public var scriptName: String
    public var type: WorkspaceScriptType
    /// Local proxy hostname, even while the script is stopped.
    public var hostname: String
    /// `nil` until an auto-assigned service has a port.
    public var port: Int?
    public var localProxyUrl: String?
    public var publicProxyUrl: String?
    /// Public URL when configured, otherwise local.
    public var proxyUrl: String?
    public var lifecycle: WorkspaceScriptLifecycle
    /// Plain scripts report `nil`; services are probed by the daemon.
    public var health: WorkspaceScriptHealth?
    public var exitCode: Int?
    /// The backing terminal. Killing it also stops the script.
    public var terminalId: String?

    public var id: String { scriptName }

    public init(
        scriptName: String, type: WorkspaceScriptType = .service, hostname: String,
        port: Int? = nil, localProxyUrl: String? = nil, publicProxyUrl: String? = nil,
        proxyUrl: String? = nil, lifecycle: WorkspaceScriptLifecycle,
        health: WorkspaceScriptHealth? = nil, exitCode: Int? = nil, terminalId: String? = nil
    ) {
        self.scriptName = scriptName
        self.type = type
        self.hostname = hostname
        self.port = port
        self.localProxyUrl = localProxyUrl
        self.publicProxyUrl = publicProxyUrl
        self.proxyUrl = proxyUrl
        self.lifecycle = lifecycle
        self.health = health
        self.exitCode = exitCode
        self.terminalId = terminalId
    }

    private enum K: String, CodingKey {
        case scriptName, type, hostname, port, localProxyUrl, publicProxyUrl, proxyUrl
        case lifecycle, health, exitCode, terminalId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        scriptName = try c.decode(String.self, forKey: .scriptName)
        type = WorkspaceScriptType(
            rawValue: try c.decodeIfPresent(String.self, forKey: .type) ?? "service")
        hostname = try c.decode(String.self, forKey: .hostname)
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        localProxyUrl = try c.decodeIfPresent(String.self, forKey: .localProxyUrl)
        publicProxyUrl = try c.decodeIfPresent(String.self, forKey: .publicProxyUrl)
        proxyUrl = try c.decodeIfPresent(String.self, forKey: .proxyUrl)
        lifecycle = try c.decode(WorkspaceScriptLifecycle.self, forKey: .lifecycle)
        health = try c.decodeIfPresent(WorkspaceScriptHealth.self, forKey: .health)
        exitCode = try c.decodeIfPresent(Int.self, forKey: .exitCode)
        terminalId = try c.decodeIfPresent(String.self, forKey: .terminalId)
    }

    /// `localProxyUrl`, `publicProxyUrl`, then the wire's combined `proxyUrl`.
    public var preferredURL: String? { localProxyUrl ?? publicProxyUrl ?? proxyUrl }
}

// Source: messages.ts `WorkspaceScriptOperationPayloadSchema`. Shared by list/start/stop.
public struct WorkspaceScriptOperation: Sendable, Decodable {
    public var requestId: String
    public var workspaceId: String
    public var scriptName: String?
    public var script: WorkspaceScript?
    /// The refreshed full list after a successful start/stop; also the list response body.
    public var scripts: [WorkspaceScript]?
    public var error: String?
}

// Source: messages.ts `WorkspaceScriptListRequestSchema`,
// `WorkspaceScriptListResponseMessageSchema`.
public struct ListWorkspaceScriptsRequest: PaseoRequest {
    public static let type = "workspace.script.list.request"
    public static let responseType = "workspace.script.list.response"
    public var requestId = ""
    public var workspaceId: String
    public init(workspaceId: String) { self.workspaceId = workspaceId }

    public typealias Response = WorkspaceScriptOperation
}

// Source: messages.ts `WorkspaceScriptStartRequestSchema`,
// `WorkspaceScriptStartResponseMessageSchema`.
public struct StartWorkspaceScriptRequest: PaseoRequest {
    public static let type = "workspace.script.start.request"
    public static let responseType = "workspace.script.start.response"
    public var requestId = ""
    public var workspaceId: String
    public var scriptName: String

    public init(workspaceId: String, scriptName: String) {
        self.workspaceId = workspaceId
        self.scriptName = scriptName
    }

    public typealias Response = WorkspaceScriptOperation
}

// Source: messages.ts `WorkspaceScriptStopRequestSchema`,
// `WorkspaceScriptStopResponseMessageSchema`.
public struct StopWorkspaceScriptRequest: PaseoRequest {
    public static let type = "workspace.script.stop.request"
    public static let responseType = "workspace.script.stop.response"
    public var requestId = ""
    public var workspaceId: String
    public var scriptName: String

    public init(workspaceId: String, scriptName: String) {
        self.workspaceId = workspaceId
        self.scriptName = scriptName
    }

    public typealias Response = WorkspaceScriptOperation
}

// Source: messages.ts `ScriptStatusUpdateMessageSchema`.
public struct ScriptStatusUpdate: Sendable, Decodable {
    public var subscriptionId: String?
    public var workspaceId: String
    public var scripts: [WorkspaceScript]
}
