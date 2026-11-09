import Foundation

// Agent timeline items. Source: packages/protocol/src/messages.ts,
// `AgentTimelineItemPayloadSchema` and `ToolCallDetailPayloadSchema`.
//
// Forward compatibility rule: a newer daemon may add item types, tool detail types, statuses and
// fields. Every union here decodes what it doesn't know into an `.unknown` case instead of throwing,
// so one new item type never breaks a whole timeline page.

public enum TimelineItem: Sendable, Hashable, Decodable {
    case userMessage(UserMessage)
    case assistantMessage(AssistantMessage)
    case reasoning(Reasoning)
    case toolCall(ToolCall)
    case todo(TodoList)
    case error(message: String)
    case notification(level: String, message: String)
    /// `messages.ts:772-776`: `status` is always there; `trigger` (`auto` / `manual`) and the
    /// context size before compaction arrived later and old daemons send neither.
    case compaction(status: String, trigger: String? = nil, preTokens: Int? = nil)
    /// `plugin` items and anything newer than this client.
    case unknown(type: String, raw: JSONValue)

    public struct UserMessage: Sendable, Hashable, Decodable {
        public var text: String
        public var messageId: String?
        public var clientMessageId: String?
        /// Attribution added by presentation for received agent messages (upstream
        /// `app/src/types/stream.ts:97`, `UserMessageItem.sender`). Never on the wire
        /// `user_message` item (`protocol/src/agent-types.ts:403`); our timeline builder
        /// fills it when projecting an agent-sourced tool call (see TimelineState).
        public var sender: AgentMessage.Sender?
        public init(text: String, messageId: String? = nil, clientMessageId: String? = nil, sender: AgentMessage.Sender? = nil) {
            self.text = text; self.messageId = messageId; self.clientMessageId = clientMessageId; self.sender = sender
        }
    }

    /// `protocol/src/agent-message.ts:4-12` (`AgentMessageSchema`): semantic provenance for
    /// agent-originated prompts. Forward compatibility: unknown events decode to `.unknown`
    /// so a newer daemon never breaks a timeline page; only `.message` is ever projected.
    public struct AgentMessage: Sendable, Hashable, Decodable {
        public enum Event: Sendable, Hashable, Decodable {
            case message, finished, errored, permissionRequired, closed
            case unknown(String)
            public init(from decoder: Decoder) throws {
                switch try decoder.singleValueContainer().decode(String.self) {
                case "message": self = .message
                case "finished": self = .finished
                case "errored": self = .errored
                case "permission-required": self = .permissionRequired
                case "closed": self = .closed
                case let other: self = .unknown(other)
                }
            }
        }
        public struct Sender: Sendable, Hashable, Decodable {
            public var id: String
            public var serverId: String?
            public var title: String?
            public init(id: String, serverId: String? = nil, title: String? = nil) {
                self.id = id; self.serverId = serverId; self.title = title
            }
        }
        public var event: Event
        public var sender: Sender
        public var text: String
        public init(event: Event, sender: Sender, text: String) {
            self.event = event; self.sender = sender; self.text = text
        }
    }

    public struct AssistantMessage: Sendable, Hashable, Decodable {
        public var text: String
        public var messageId: String?
        public init(text: String, messageId: String? = nil) { self.text = text; self.messageId = messageId }
    }

    public struct Reasoning: Sendable, Hashable, Decodable {
        public var text: String
        public init(text: String) { self.text = text }
    }

    public struct TodoList: Sendable, Hashable, Decodable {
        public var items: [Todo]
        public struct Todo: Sendable, Hashable, Decodable {
            public var text: String
            public var completed: Bool
            public var id: String?
            /// `pending`, `in_progress`, `completed`.
            public var status: String?
            public var activeForm: String?
        }
    }

    private enum K: String, CodingKey { case message, level, status, trigger, preTokens }

    public init(from decoder: Decoder) throws {
        let type = try decoder.discriminator()
        switch type {
        case "user_message": self = .userMessage(try UserMessage(from: decoder))
        case "assistant_message": self = .assistantMessage(try AssistantMessage(from: decoder))
        case "reasoning": self = .reasoning(try Reasoning(from: decoder))
        case "tool_call": self = .toolCall(try ToolCall(from: decoder))
        case "todo": self = .todo(try TodoList(from: decoder))
        case "error":
            self = .error(message: try decoder.container(keyedBy: K.self).decode(String.self, forKey: .message))
        case "notification":
            let c = try decoder.container(keyedBy: K.self)
            self = .notification(level: try c.decode(String.self, forKey: .level), message: try c.decode(String.self, forKey: .message))
        case "compaction":
            let c = try decoder.container(keyedBy: K.self)
            self = .compaction(
                status: try c.decode(String.self, forKey: .status),
                trigger: try c.decodeIfPresent(String.self, forKey: .trigger),
                // Tolerant: a future payload that puts something else here must not break the page.
                preTokens: (try? c.decodeIfPresent(Int.self, forKey: .preTokens)) ?? nil)
        default:
            self = .unknown(type: type, raw: try JSONValue(from: decoder))
        }
    }
}

public struct ToolCall: Sendable, Hashable, Decodable {
    /// Stable across the call's lifecycle; a later event with the same `callId` replaces this one.
    public var callId: String
    /// Provider tool name, e.g. `Bash`, `Read`, `edit`.
    public var name: String
    public var status: Status
    public var detail: ToolCallDetail
    /// Non-null only when `status == .failed`. Usually a string, but any JSON is allowed.
    public var error: JSONValue?
    /// Upstream `protocol/src/agent-types.ts:342` (`ToolCallBase.agentMessage?`); absent on
    /// ordinary tool calls and on old payloads. When present with event `message`, the
    /// timeline renders this call as a user message (see TimelineState).
    public var agentMessage: TimelineItem.AgentMessage? = nil

    public enum Status: Sendable, Hashable, Decodable {
        case running, completed, failed, canceled
        case unknown(String)
        public init(from decoder: Decoder) throws {
            switch try decoder.singleValueContainer().decode(String.self) {
            case "running": self = .running
            case "completed": self = .completed
            case "failed": self = .failed
            case "canceled": self = .canceled
            case let other: self = .unknown(other)
            }
        }
        public var isTerminal: Bool { if case .running = self { false } else { true } }
    }
}

public enum ToolCallDetail: Sendable, Hashable, Decodable {
    case shell(command: String, cwd: String?, output: String?, exitCode: Double?)
    case read(filePath: String, content: String?)
    case edit(filePath: String, oldString: String?, newString: String?, unifiedDiff: String?)
    case write(filePath: String, content: String?)
    case search(Search)
    case fetch(url: String, result: String?, code: Double?)
    case subAgent(subAgentType: String?, description: String?, childSessionId: String?)
    case plainText(label: String?, text: String?, icon: String?)
    case plan(text: String)
    case worktreeSetup(worktreePath: String, branchName: String, log: String)
    /// The daemon's own `unknown` detail (input/output not normalized yet) and any newer type.
    case unknown(type: String, raw: JSONValue)

    public struct Search: Sendable, Hashable, Decodable {
        public var query: String
        /// `search`, `grep`, `glob`, `web_search`.
        public var toolName: String?
        public var content: String?
        public var filePaths: [String]?
        public var webResults: [WebResult]?
        public var numFiles: Double?
        public var numMatches: Double?
        public struct WebResult: Sendable, Hashable, Decodable {
            public var title: String
            public var url: String
        }
    }

    private enum K: String, CodingKey {
        case command, cwd, output, exitCode, filePath, content, oldString, newString, unifiedDiff
        case url, result, code, subAgentType, description, childSessionId, label, text, icon
        case worktreePath, branchName, log
    }

    public init(from decoder: Decoder) throws {
        let type = try decoder.discriminator()
        let c = try decoder.container(keyedBy: K.self)
        switch type {
        case "shell":
            self = .shell(
                command: try c.decode(String.self, forKey: .command), cwd: try c.decodeIfPresent(String.self, forKey: .cwd),
                output: try c.decodeIfPresent(String.self, forKey: .output), exitCode: try c.decodeIfPresent(Double.self, forKey: .exitCode))
        case "read":
            self = .read(filePath: try c.decode(String.self, forKey: .filePath), content: try c.decodeIfPresent(String.self, forKey: .content))
        case "edit":
            self = .edit(
                filePath: try c.decode(String.self, forKey: .filePath), oldString: try c.decodeIfPresent(String.self, forKey: .oldString),
                newString: try c.decodeIfPresent(String.self, forKey: .newString), unifiedDiff: try c.decodeIfPresent(String.self, forKey: .unifiedDiff))
        case "write":
            self = .write(filePath: try c.decode(String.self, forKey: .filePath), content: try c.decodeIfPresent(String.self, forKey: .content))
        case "search": self = .search(try Search(from: decoder))
        case "fetch":
            self = .fetch(url: try c.decode(String.self, forKey: .url), result: try c.decodeIfPresent(String.self, forKey: .result), code: try c.decodeIfPresent(Double.self, forKey: .code))
        case "sub_agent":
            self = .subAgent(
                subAgentType: try c.decodeIfPresent(String.self, forKey: .subAgentType), description: try c.decodeIfPresent(String.self, forKey: .description),
                childSessionId: try c.decodeIfPresent(String.self, forKey: .childSessionId))
        case "plain_text":
            self = .plainText(label: try c.decodeIfPresent(String.self, forKey: .label), text: try c.decodeIfPresent(String.self, forKey: .text), icon: try c.decodeIfPresent(String.self, forKey: .icon))
        case "plan": self = .plan(text: try c.decode(String.self, forKey: .text))
        case "worktree_setup":
            self = .worktreeSetup(worktreePath: try c.decode(String.self, forKey: .worktreePath), branchName: try c.decode(String.self, forKey: .branchName), log: try c.decode(String.self, forKey: .log))
        default:
            self = .unknown(type: type, raw: try JSONValue(from: decoder))
        }
    }
}

/// One projected row from `fetch_agent_timeline_response`. Projection already merged chunks and
/// tool lifecycles; `seqStart...seqEnd` covers the source events it absorbed.
public struct TimelineEntry: Sendable, Hashable, Decodable {
    public var provider: String
    public var item: TimelineItem
    public var turnId: String?
    /// ISO-8601.
    public var timestamp: String
    public var seqStart: Int
    public var seqEnd: Int
}

public struct TimelineCursor: Sendable, Hashable, Codable {
    public var epoch: String
    public var seq: Int
    public init(epoch: String, seq: Int) { self.epoch = epoch; self.seq = seq }
}
