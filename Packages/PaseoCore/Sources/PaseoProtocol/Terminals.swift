import Foundation

// Terminals: directory listings, create/kill/capture, attach, input and the binary stream codec.
//
// Source: packages/protocol/src/messages.ts `ListTerminalsRequestSchema`,
// `SubscribeTerminalsRequestSchema`, `CreateTerminalRequestSchema`, `SubscribeTerminalRequestSchema`,
// `TerminalInputSchema`, `KillTerminalRequestSchema`, `CaptureTerminalRequestSchema`, the matching
// outbound schemas, `TerminalInfoSchema` and `TerminalActivitySchema`.
// Source: packages/protocol/src/binary-frames/terminal.ts for the opcodes and byte layout.
//
// Forward compatibility: every union has an `.unknown` case, every field a newer daemon might add
// is optional, and no decoder throws over extra fields.

/// A grid size in terminal cells. Used by `create_terminal_request`, `restore.size` and resize.
public struct TerminalSize: Sendable, Hashable, Codable {
    public var rows: Int
    public var cols: Int
    public init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
    }
}

// Source: messages.ts `TerminalActivitySchema`.
public enum TerminalActivityState: Sendable, Hashable, Decodable {
    case idle, working, attention
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "idle": self = .idle
        case "working": self = .working
        case "attention": self = .attention
        case let other: self = .unknown(other)
        }
    }
}

// Source: messages.ts `TerminalActivitySchema.attentionReason`.
public enum TerminalAttentionReason: Sendable, Hashable, Decodable {
    case finished
    case needsInput
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "finished": self = .finished
        case "needs_input": self = .needsInput
        case let other: self = .unknown(other)
        }
    }
}

/// What the tab dot should show. Derived exactly like upstream
/// `deriveTerminalActivityStatusBucket` (`packages/protocol/src/terminal-activity.ts`).
public enum TerminalActivityBucket: Sendable, Hashable {
    case needsInput
    case attention
    case running
}

public struct TerminalActivity: Sendable, Hashable, Decodable {
    public var state: TerminalActivityState
    public var attentionReason: TerminalAttentionReason?
    /// Milliseconds since the epoch, as the daemon sends it.
    public var changedAt: Double

    public init(
        state: TerminalActivityState, attentionReason: TerminalAttentionReason? = nil,
        changedAt: Double = 0
    ) {
        self.state = state
        self.attentionReason = attentionReason
        self.changedAt = changedAt
    }

    private enum K: String, CodingKey { case state, attentionReason, changedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        if let raw = try c.decodeIfPresent(String.self, forKey: .state) {
            state = TerminalActivityState(rawValue: raw)
        } else {
            // The schema's `.catch()` degrades unknown activity to idle. Missing is no better.
            state = .idle
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .attentionReason) {
            attentionReason = TerminalAttentionReason(rawValue: raw)
        } else {
            attentionReason = nil
        }
        changedAt = try c.decodeIfPresent(Double.self, forKey: .changedAt) ?? 0
    }

    public var statusBucket: TerminalActivityBucket? {
        switch attentionReason {
        case .needsInput: return .needsInput
        case .finished: return .attention
        default: break
        }
        switch state {
        case .working: return .running
        // Upstream buckets a bare `attention` state as needs_input even without a reason.
        case .attention: return .needsInput
        case .idle, .unknown: return nil
        }
    }
}

extension TerminalActivityState {
    init(rawValue: String) {
        switch rawValue {
        case "idle": self = .idle
        case "working": self = .working
        case "attention": self = .attention
        case let other: self = .unknown(other)
        }
    }
}

extension TerminalAttentionReason {
    init(rawValue: String) {
        switch rawValue {
        case "finished": self = .finished
        case "needs_input": self = .needsInput
        case let other: self = .unknown(other)
        }
    }
}

// Source: messages.ts `TerminalInfoSchema`. `cwd` is optional on the wire (`.partial({ cwd: true })`).
public struct TerminalInfo: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var name: String
    public var cwd: String?
    public var workspaceId: String?
    public var title: String?
    public var isScript: Bool?
    public var createdAt: String?
    public var activity: TerminalActivity?

    public init(
        id: String, name: String, cwd: String? = nil, workspaceId: String? = nil,
        title: String? = nil, isScript: Bool? = nil, createdAt: String? = nil,
        activity: TerminalActivity? = nil
    ) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.workspaceId = workspaceId
        self.title = title
        self.isScript = isScript
        self.createdAt = createdAt
        self.activity = activity
    }

    public var activityBucket: TerminalActivityBucket? { activity?.statusBucket }
}

// Source: messages.ts `ListTerminalsRequestSchema`, `ListTerminalsResponseSchema`.
public struct ListTerminalsRequest: PaseoRequest {
    public static let type = "list_terminals_request"
    public static let responseType = "list_terminals_response"
    public var requestId = ""
    public var cwd: String?
    public var workspaceId: String?

    public init(cwd: String? = nil, workspaceId: String? = nil) {
        self.cwd = cwd
        self.workspaceId = workspaceId
    }

    public struct Response: Decodable, Sendable {
        public var cwd: String?
        public var terminals: [TerminalInfo]
        public var requestId: String
    }
}

// Source: messages.ts `SubscribeTerminalsRequestSchema`. No response; snapshots arrive as
// `terminals_changed`.
public struct SubscribeTerminalsRequest: PaseoOutboundMessage {
    public static let type = "subscribe_terminals_request"
    public var requestId: String?
    public var cwd: String?
    public var workspaceId: String?

    public init(cwd: String? = nil, workspaceId: String? = nil, requestId: String? = nil) {
        self.cwd = cwd
        self.workspaceId = workspaceId
        self.requestId = requestId
    }
}

// Source: messages.ts `UnsubscribeTerminalsRequestSchema`.
public struct UnsubscribeTerminalsRequest: PaseoOutboundMessage {
    public static let type = "unsubscribe_terminals_request"
    public var cwd: String?
    public var workspaceId: String?

    public init(cwd: String? = nil, workspaceId: String? = nil) {
        self.cwd = cwd
        self.workspaceId = workspaceId
    }
}

// Source: messages.ts `CreateTerminalRequestSchema`, `CreateTerminalResponseSchema`.
public struct CreateTerminalRequest: PaseoRequest {
    public static let type = "create_terminal_request"
    public static let responseType = "create_terminal_response"
    public var requestId = ""
    public var cwd: String
    public var workspaceId: String?
    public var name: String?
    public var agentId: String?
    public var command: String?
    public var args: [String]?
    public var size: TerminalSize?

    public init(
        cwd: String, workspaceId: String? = nil, name: String? = nil, agentId: String? = nil,
        command: String? = nil, args: [String]? = nil, size: TerminalSize? = nil
    ) {
        self.cwd = cwd
        self.workspaceId = workspaceId
        self.name = name
        self.agentId = agentId
        self.command = command
        self.args = args
        self.size = size
    }

    public struct Response: Decodable, Sendable {
        public var terminal: TerminalInfo?
        public var error: String?
        public var requestId: String
    }
}

// Source: messages.ts `SubscribeTerminalRequestSchema`. Outbound only; the daemon never sends it.
public enum TerminalRestoreMode: String, Sendable, Hashable, Encodable {
    case live
    case visibleSnapshot = "visible-snapshot"
    case fullSnapshot = "full-snapshot"
}

public struct TerminalRestoreOptions: Sendable, Hashable, Encodable {
    public var mode: TerminalRestoreMode
    public var scrollbackLines: Int?
    public var size: TerminalSize?

    public init(mode: TerminalRestoreMode, scrollbackLines: Int? = nil, size: TerminalSize? = nil) {
        self.mode = mode
        self.scrollbackLines = scrollbackLines
        self.size = size
    }

    /// Daemon default for `visible-snapshot` is 200 retained lines.
    public static let visibleSnapshot = TerminalRestoreOptions(
        mode: .visibleSnapshot, scrollbackLines: 200)
    public static let live = TerminalRestoreOptions(mode: .live)
    public static let fullSnapshot = TerminalRestoreOptions(mode: .fullSnapshot)
}

// Source: messages.ts `SubscribeTerminalRequestSchema`, `SubscribeTerminalResponseSchema`.
public struct SubscribeTerminalRequest: PaseoRequest {
    public static let type = "subscribe_terminal_request"
    public static let responseType = "subscribe_terminal_response"
    public var requestId = ""
    public var terminalId: String
    public var restore: TerminalRestoreOptions?

    public init(terminalId: String, restore: TerminalRestoreOptions? = nil) {
        self.terminalId = terminalId
        self.restore = restore
    }

    /// The success branch carries `slot`/`subscriptionId`; the failure branch carries only an
    /// error string. Discriminate on `error == nil && slot != nil`, never on the presence of a key.
    public struct Response: Decodable, Sendable {
        public var terminalId: String
        public var requestId: String
        public var slot: UInt8?
        public var subscriptionId: String?
        public var error: String?

        private enum K: String, CodingKey { case terminalId, requestId, slot, subscriptionId, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            terminalId = try c.decode(String.self, forKey: .terminalId)
            requestId = try c.decode(String.self, forKey: .requestId)
            slot = try c.decodeIfPresent(Int.self, forKey: .slot).flatMap(UInt8.init(exactly:))
            subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId)
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}

// Source: messages.ts `UnsubscribeTerminalRequestSchema`. Legacy detach path; no response.
public struct UnsubscribeTerminalRequest: PaseoOutboundMessage {
    public static let type = "unsubscribe_terminal_request"
    public var terminalId: String
    public init(terminalId: String) { self.terminalId = terminalId }
}

// Source: messages.ts `TerminalClientMessageSchema`, `TerminalInputSchema`.
public enum TerminalResizeIntent: String, Sendable, Hashable, Encodable {
    case claim
    case update
}

public enum TerminalMouseAction: String, Sendable, Hashable, Encodable {
    case down
    case up
    case move
}

public struct TerminalInput: PaseoOutboundMessage {
    public static let type = "terminal_input"
    public var terminalId: String
    public var message: Message

    public init(terminalId: String, message: Message) {
        self.terminalId = terminalId
        self.message = message
    }

    public static func input(_ data: String, terminalId: String) -> TerminalInput {
        TerminalInput(terminalId: terminalId, message: .input(data: data))
    }

    public static func resize(
        rows: Int, cols: Int, intent: TerminalResizeIntent?, terminalId: String
    ) -> TerminalInput {
        TerminalInput(
            terminalId: terminalId, message: .resize(rows: rows, cols: cols, intent: intent))
    }

    public static func mouse(
        row: Int, col: Int, button: Int, action: TerminalMouseAction, terminalId: String
    ) -> TerminalInput {
        TerminalInput(
            terminalId: terminalId,
            message: .mouse(row: row, col: col, button: button, action: action))
    }

    public enum Message: Sendable, Hashable {
        case input(data: String)
        case resize(rows: Int, cols: Int, intent: TerminalResizeIntent?)
        case mouse(row: Int, col: Int, button: Int, action: TerminalMouseAction)
    }

    private enum K: String, CodingKey { case terminalId, message }
    private enum M: String, CodingKey { case type, data, rows, cols, intent, row, col, button, action }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(terminalId, forKey: .terminalId)
        var m = c.nestedContainer(keyedBy: M.self, forKey: .message)
        switch message {
        case .input(let data):
            try m.encode("input", forKey: .type)
            try m.encode(data, forKey: .data)
        case .resize(let rows, let cols, let intent):
            try m.encode("resize", forKey: .type)
            try m.encode(rows, forKey: .rows)
            try m.encode(cols, forKey: .cols)
            try m.encodeIfPresent(intent, forKey: .intent)
        case .mouse(let row, let col, let button, let action):
            try m.encode("mouse", forKey: .type)
            try m.encode(row, forKey: .row)
            try m.encode(col, forKey: .col)
            try m.encode(button, forKey: .button)
            try m.encode(action, forKey: .action)
        }
    }
}

// Source: messages.ts `KillTerminalRequestSchema`, `KillTerminalResponseSchema`.
public struct KillTerminalRequest: PaseoRequest {
    public static let type = "kill_terminal_request"
    public static let responseType = "kill_terminal_response"
    public var requestId = ""
    public var terminalId: String
    public init(terminalId: String) { self.terminalId = terminalId }

    public struct Response: Decodable, Sendable {
        public var terminalId: String
        public var success: Bool
        public var requestId: String
    }
}

// Source: messages.ts `CaptureTerminalRequestSchema`, `CaptureTerminalResponseSchema`.
public struct CaptureTerminalRequest: PaseoRequest {
    public static let type = "capture_terminal_request"
    public static let responseType = "capture_terminal_response"
    public var requestId = ""
    public var terminalId: String
    public var start: Int?
    public var end: Int?
    /// Wire default is `true`.
    public var stripAnsi: Bool

    public init(terminalId: String, start: Int? = nil, end: Int? = nil, stripAnsi: Bool = true) {
        self.terminalId = terminalId
        self.start = start
        self.end = end
        self.stripAnsi = stripAnsi
    }

    public struct Response: Decodable, Sendable {
        public var terminalId: String
        public var lines: [String]
        public var totalLines: Int
        public var requestId: String
    }
}

// Source: messages.ts `TerminalsChangedSchema`.
public struct TerminalsChanged: Sendable, Decodable {
    public var subscriptionId: String?
    public var requestId: String?
    public var workspaceId: String?
    public var cwd: String?
    public var terminals: [TerminalInfo]
}

// Source: messages.ts `TerminalStreamExitSchema`.
public struct TerminalStreamExit: Sendable, Decodable, Equatable {
    public var subscriptionId: String?
    public var terminalId: String
    /// Observation failure; the underlying process may still be running.
    public var error: String?
}

// Source: messages.ts `TerminalAttentionRequiredSchema`.
public struct TerminalAttentionRequired: Sendable, Decodable, Equatable {
    public var subscriptionId: String?
    public var serverId: String?
    public var terminalId: String
    public var cwd: String
    public var workspaceId: String?
    public var reason: TerminalAttentionReason
    public var title: String
    public var body: String
    public var shouldNotify: Bool
}

// MARK: - Binary terminal stream codec

/// Source: `packages/protocol/src/binary-frames/terminal.ts` `TerminalStreamOpcode`.
public enum TerminalStreamOpcode: Sendable, Hashable {
    case output
    case input
    case resize
    case snapshot
    case restore
    case replayBegin
    case replayData
    case replayEnd
    case unknown(UInt8)

    public var rawValue: UInt8 {
        switch self {
        case .output: return 0x01
        case .input: return 0x02
        case .resize: return 0x03
        case .snapshot: return 0x04
        case .restore: return 0x05
        case .replayBegin: return 0x06
        case .replayData: return 0x07
        case .replayEnd: return 0x08
        case .unknown(let value): return value
        }
    }

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0x01: self = .output
        case 0x02: self = .input
        case 0x03: self = .resize
        case 0x04: self = .snapshot
        case 0x05: self = .restore
        case 0x06: self = .replayBegin
        case 0x07: self = .replayData
        case 0x08: self = .replayEnd
        default: self = .unknown(rawValue)
        }
    }
}

/// One terminal stream frame: `[opcode: 1][slot: 1][payload: n]`.
public struct TerminalStreamFrame: Sendable, Hashable {
    public var opcode: TerminalStreamOpcode
    public var slot: UInt8
    public var payload: Data

    public init(opcode: TerminalStreamOpcode, slot: UInt8, payload: Data = Data()) {
        self.opcode = opcode
        self.slot = slot
        self.payload = payload
    }

    /// Returns `nil` for fewer than two bytes. Unknown opcodes decode into `.unknown` rather than
    /// failing, so a newer daemon's frames can be ignored by opcode instead of dropped by length.
    public init?(decoding data: Data) {
        guard data.count >= 2 else { return nil }
        let bytes = [UInt8](data)
        opcode = TerminalStreamOpcode(rawValue: bytes[0])
        slot = bytes[1]
        payload = data.dropFirst(2)
    }

    public var encoded: Data {
        var data = Data([opcode.rawValue, slot])
        data.append(payload)
        return data
    }

    /// The JSON body of `ReplayBegin` (0x06). `nil` when the body is not valid metadata.
    public var replayMetadata: TerminalReplayMetadata? {
        try? JSONDecoder().decode(TerminalReplayMetadata.self, from: payload)
    }
}

// Source: binary-frames/terminal.ts `TerminalReplayMetadataSchema`.
public struct TerminalReplayMetadata: Sendable, Hashable, Decodable {
    public var rows: Int
    public var cols: Int
    public var retainedHistoryLines: Int

    public init(rows: Int, cols: Int, retainedHistoryLines: Int) {
        self.rows = rows
        self.cols = cols
        self.retainedHistoryLines = retainedHistoryLines
    }
}

// Source: binary-frames/terminal.ts `TerminalStreamResizeSchema`.
public struct TerminalStreamResize: Sendable, Hashable, Decodable {
    public var rows: Int
    public var cols: Int
    public var intent: String?

    public init(rows: Int, cols: Int, intent: String? = nil) {
        self.rows = rows
        self.cols = cols
        self.intent = intent
    }
}

// Source: binary-frames/terminal.ts `encodeTerminalStreamFrame` / `decodeTerminalStreamFrame`.
public enum TerminalStreamCodec {
    public static func encode(_ frame: TerminalStreamFrame) -> Data { frame.encoded }

    public static func decode(_ data: Data) -> TerminalStreamFrame? {
        TerminalStreamFrame(decoding: data)
    }
}
