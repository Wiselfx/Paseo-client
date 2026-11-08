import Foundation
import PaseoKit
import PaseoProtocol

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

// Live smoke test for DaemonConnection. See docs/tickets/T1-daemon-connection.md.
//   swift run paseo-probe [--url ws://127.0.0.1:6767/ws] [--local-credential PATH | --password-env VAR] <command>

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct ParsedArguments {
    var url: URL
    var localCredentialPath: String?
    var passwordEnvironmentVariable: String?
    var command: String
    var commandArguments: [String]
}

let usage = """
    usage: paseo-probe [--url ws://127.0.0.1:6767/ws] [--local-credential PATH | --password-env VAR] <command>

    commands:
      info                     print server id, version, protocol version
      agents                   list agents: id prefix, provider, status, title
      timeline <agentId>       fetch the tail; one line per entry: seq, type, short text
      watch <agentId> [secs]   subscribe and print each stream event's seq and type (default 30s)

    Default credential: --local-credential /home/paseo/.paseo/local-credential
    """

func parseArguments(_ raw: [String]) throws -> ParsedArguments {
    var urlString = "ws://127.0.0.1:6767/ws"
    var localCredentialPath: String? = "/home/paseo/.paseo/local-credential"
    var passwordEnvironmentVariable: String?
    var command: String?
    var commandArguments: [String] = []

    var index = 0
    while index < raw.count {
        let argument = raw[index]
        switch argument {
        case "--help", "-h":
            print(usage)
            exit(0)
        case "--url":
            index += 1
            guard index < raw.count else { throw ProbeError("--url needs a value") }
            urlString = raw[index]
        case "--local-credential":
            index += 1
            guard index < raw.count else { throw ProbeError("--local-credential needs a path") }
            localCredentialPath = raw[index]
            passwordEnvironmentVariable = nil
        case "--password-env":
            index += 1
            guard index < raw.count else { throw ProbeError("--password-env needs a variable name") }
            passwordEnvironmentVariable = raw[index]
            localCredentialPath = nil
        default:
            if argument.hasPrefix("--") {
                throw ProbeError("unknown option \(argument)")
            }
            if command == nil {
                command = argument
            } else {
                commandArguments.append(argument)
            }
        }
        index += 1
    }

    guard let command else {
        throw ProbeError("missing command\n\n\(usage)")
    }
    guard let url = URL(string: urlString) else {
        throw ProbeError("invalid URL: \(urlString)")
    }

    return ParsedArguments(
        url: url,
        localCredentialPath: localCredentialPath,
        passwordEnvironmentVariable: passwordEnvironmentVariable,
        command: command,
        commandArguments: commandArguments
    )
}

func resolveCredential(_ arguments: ParsedArguments) throws -> Credential? {
    if let variable = arguments.passwordEnvironmentVariable {
        guard let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty else {
            throw ProbeError("environment variable \(variable) is not set")
        }
        return .password(value)
    }
    if let path = arguments.localCredentialPath {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ProbeError("cannot read local credential at \(path)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProbeError("local credential at \(path) is not UTF-8")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProbeError("local credential at \(path) is empty")
        }
        return .localCredential(trimmed)
    }
    return nil
}

func makeConnection(_ arguments: ParsedArguments) throws -> DaemonConnection {
    DaemonConnection(
        endpoint: DaemonEndpoint(url: arguments.url, credential: try resolveCredential(arguments)),
        clientId: "paseo-probe-\(UUID().uuidString.prefix(8))",
        appVersion: nil
    )
}

func statusText(_ status: AgentStatus) -> String {
    switch status {
    case .initializing: "initializing"
    case .idle: "idle"
    case .running: "running"
    case .error: "error"
    case .closed: "closed"
    case .unknown(let raw): raw
    }
}

func itemType(_ item: TimelineItem) -> String {
    switch item {
    case .userMessage: "user_message"
    case .assistantMessage: "assistant_message"
    case .reasoning: "reasoning"
    case .toolCall: "tool_call"
    case .todo: "todo"
    case .error: "error"
    case .notification: "notification"
    case .compaction: "compaction"
    case .unknown(let type, _): type
    }
}

func shortText(_ item: TimelineItem) -> String {
    let text: String
    switch item {
    case .userMessage(let message): text = message.text
    case .assistantMessage(let message): text = message.text
    case .reasoning(let reasoning): text = reasoning.text
    case .toolCall(let call): text = "\(call.name) [\(toolStatusText(call.status))]"
    case .todo(let list): text = "\(list.items.count) todos"
    case .error(let message): text = message
    case .notification(let level, let message): text = "\(level): \(message)"
    case .compaction(let status): text = status
    case .unknown(let type, _): text = type
    }
    let singleLine = text.replacingOccurrences(of: "\n", with: " ")
    return String(singleLine.prefix(80))
}

func toolStatusText(_ status: ToolCall.Status) -> String {
    switch status {
    case .running: "running"
    case .completed: "completed"
    case .failed: "failed"
    case .canceled: "canceled"
    case .unknown(let raw): raw
    }
}

func streamEventType(_ event: AgentStreamEvent) -> String {
    switch event {
    case .turnStarted: "turn_started"
    case .turnCompleted: "turn_completed"
    case .turnFailed: "turn_failed"
    case .turnCanceled: "turn_canceled"
    case .timeline: "timeline"
    case .permissionRequested: "permission_requested"
    case .permissionResolved: "permission_resolved"
    case .attentionRequired: "attention_required"
    case .unknown(let type): type
    }
}

func runInfo(_ connection: DaemonConnection) async throws {
    let info = try await connection.connect()
    print("serverId: \(info.serverId)")
    print("version: \(info.version ?? "-")")
    print("protocolVersion: \(info.protocolVersion.map(String.init) ?? "-")")
}

func runAgents(_ connection: DaemonConnection) async throws {
    _ = try await connection.connect()
    let response = try await connection.send(
        FetchAgentsRequest(page: FetchAgentsRequest.Page(limit: 100)))
    for entry in response.entries {
        let agent = entry.agent
        let idPrefix = String(agent.id.prefix(8))
        print("\(idPrefix)  \(agent.provider)  \(statusText(agent.status))  \(agent.title ?? "-")")
    }
    print("\(response.entries.count) agents")
}

func runTimeline(_ connection: DaemonConnection, agentId: String) async throws {
    _ = try await connection.connect()
    let response = try await connection.send(
        FetchAgentTimelineRequest(agentId: agentId, direction: .tail, limit: 20))
    print(
        "agent \(response.agentId) epoch \(response.epoch) window \(response.window.minSeq)...\(response.window.maxSeq)"
    )
    for entry in response.entries {
        print("\(entry.seqStart)...\(entry.seqEnd)  \(itemType(entry.item))  \(shortText(entry.item))")
    }
    print("\(response.entries.count) entries hasOlder=\(response.hasOlder)")
}

func runWatch(_ connection: DaemonConnection, agentId: String, seconds: Int) async throws {
    _ = try await connection.connect()
    let response = try await connection.send(SetAgentTimelineSubscriptionRequest(agentIds: [agentId]))
    print("subscribed \(response.agentIds.joined(separator: ",")) for \(seconds)s")

    let printer = Task {
        for await event in connection.events {
            guard case .agentStream(let payload) = event else { continue }
            let seq = payload.seq.map(String.init) ?? "-"
            print("seq=\(seq)  type=\(streamEventType(payload.event))")
        }
    }

    try await Task.sleep(for: .seconds(seconds))
    printer.cancel()
    connection.disconnect()
}

do {
    let arguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    let connection = try makeConnection(arguments)

    switch arguments.command {
    case "info":
        try await runInfo(connection)
    case "agents":
        try await runAgents(connection)
    case "timeline":
        guard let agentId = arguments.commandArguments.first else {
            throw ProbeError("timeline needs an <agentId>")
        }
        try await runTimeline(connection, agentId: agentId)
    case "watch":
        guard let agentId = arguments.commandArguments.first else {
            throw ProbeError("watch needs an <agentId>")
        }
        var seconds = 30
        if arguments.commandArguments.count > 1 {
            guard let parsed = Int(arguments.commandArguments[1]), parsed > 0 else {
                throw ProbeError("watch seconds must be a positive integer")
            }
            seconds = parsed
        }
        try await runWatch(connection, agentId: agentId, seconds: seconds)
    default:
        throw ProbeError("unknown command \(arguments.command)\n\n\(usage)")
    }

    connection.disconnect()
} catch {
    FileHandle.standardError.write(Data("paseo-probe: \(error)\n".utf8))
    exit(1)
}
