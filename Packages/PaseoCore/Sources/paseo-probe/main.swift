import Foundation
import PaseoKit
import PaseoProtocol
import PaseoStore

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
      chat <agentId> <text> [secs]
                               full stack (HostSession/ConversationStore): send text, print the
                               last turn as it changes until the agent finishes (default 180s)
      terminal <workspaceId> [cwd]
                               create a terminal in a workspace, attach, run `echo hello`, print
                               the escaped bytes, detach and kill it (default cwd /tmp/fixture-sandbox)

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
    case "chat":
        guard arguments.commandArguments.count >= 2 else { throw ProbeError("chat needs <agentId> <text>") }
        let seconds = arguments.commandArguments.count > 2 ? Int(arguments.commandArguments[2]) ?? 180 : 180
        try await runChat(connection, agentId: arguments.commandArguments[0], text: arguments.commandArguments[1], seconds: seconds)
    case "terminal":
        guard let workspaceId = arguments.commandArguments.first else {
            throw ProbeError("terminal needs a <workspaceId>")
        }
        let cwd = arguments.commandArguments.count > 1 ? arguments.commandArguments[1] : "/tmp/fixture-sandbox"
        try await runTerminal(connection, workspaceId: workspaceId, cwd: cwd)
    default:
        throw ProbeError("unknown command \(arguments.command)\n\n\(usage)")
    }

    connection.disconnect()
} catch {
    FileHandle.standardError.write(Data("paseo-probe: \(error)\n".utf8))
    exit(1)
}

/// End-to-end check of the layers the app uses: connection → HostSession → ConversationStore → turns.
@MainActor
func runChat(_ connection: DaemonConnection, agentId: String, text: String, seconds: Int) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    let store = session.conversation(for: agentId)
    let loadDeadline = Date().addingTimeInterval(15)
    while store.phase == .loading, Date() < loadDeadline { try await Task.sleep(for: .milliseconds(50)) }
    print("loaded: phase=\(store.phase) turns=\(store.turns.count) rows=\(store.timeline.rows.count)")

    await store.send(text)
    print("sent; actionError=\(store.actionError ?? "none")")
    var last = ""
    var sawRunning = false
    let deadline = Date().addingTimeInterval(Double(seconds))
    while Date() < deadline {
        let line = describe(store.turns.last, running: store.isRunning)
        if line != last { print(line); last = line }
        if store.isRunning { sawRunning = true }
        if sawRunning, !store.isRunning { break }
        try await Task.sleep(for: .milliseconds(150))
    }
    print("final: turns=\(store.turns.count) running=\(store.isRunning) duration=\(store.turns.last?.duration.map { String(format: "%.1fs", $0) } ?? "-")")
    if let turn = store.turns.last {
        for segment in turn.segments {
            switch segment {
            case .work(let group):
                print("  work: \(group.summary)")
                for row in group.rows {
                    if case .toolCall(let call) = row.item {
                        let p = ToolCallPresentation(call)
                        print("    \(p.title) · \(p.subtitle ?? "") [\(p.status)]")
                    }
                }
            case .prose(let row):
                if case .assistantMessage(let m) = row.item { print("  prose: \(m.text.prefix(160).replacingOccurrences(of: "\n", with: " ⏎ "))") }
            case .todo: print("  todo")
            case .notice(let row): print("  notice: \(row.item)")
            }
        }
    }
    session.closeConversation(agentId)
}

@MainActor
func runTerminal(_ connection: DaemonConnection, workspaceId: String, cwd: String) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    let store = session.terminals

    let supportDeadline = Date().addingTimeInterval(5)
    while !store.isSupported, Date() < supportDeadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    guard store.isSupported else { throw ProbeError("host does not support terminal restore modes") }
    await store.open(workspaceId: workspaceId, cwd: cwd)

    let terminal = await store.createTerminal(in: workspaceId, cwd: cwd, name: "paseo-probe")
    guard let terminal else { throw ProbeError("create terminal failed: \(store.error ?? "unknown")") }
    print("created \(terminal.id) name=\(terminal.name) cwd=\(terminal.cwd ?? "-")")

    let stream = await store.attach(terminal.id, size: TerminalSize(rows: 24, cols: 80))
    let collector = Task { () -> (bytes: Data, markers: [String]) in
        var bytes = Data()
        var markers: [String] = []
        for await output in stream {
            switch output {
            case .replayBegin(let metadata):
                markers.append(
                    "replayBegin \(metadata.rows)x\(metadata.cols) history=\(metadata.retainedHistoryLines)")
            case .output(let data):
                bytes.append(data)
            case .replayEnd:
                markers.append("replayEnd")
            case .exited(let error):
                markers.append("exited \(error ?? "closed")")
                return (bytes, markers)
            }
        }
        return (bytes, markers)
    }

    store.sendInput("printf 'hello\\n'; ls\r", to: terminal.id)
    try await Task.sleep(for: .seconds(2))
    store.detach(terminal.id)
    let received = await collector.value
    print("markers: \(received.markers.joined(separator: ", "))")
    print("bytes: \(escapedTerminalBytes(received.bytes))")

    let killed = await store.killTerminal(terminal.id)
    print("killed: \(killed) error=\(store.error ?? "none")")
    guard killed else { throw ProbeError("kill terminal failed: \(store.error ?? "unknown")") }
}

func escapedTerminalBytes(_ data: Data) -> String {
    var out = ""
    for byte in data {
        switch byte {
        case 0x0A: out += "\\n"
        case 0x0D: out += "\\r"
        case 0x09: out += "\\t"
        case 0x20..<0x7F: out.append(Character(UnicodeScalar(byte)))
        default: out += String(format: "\\x%02x", byte)
        }
    }
    return out
}

@MainActor
func describe(_ turn: Turn?, running: Bool) -> String {
    guard let turn else { return "(no turn)" }
    let user: String = if case .userMessage(let m)? = turn.userMessage?.item { String(m.text.prefix(30)) } else { "-" }
    let pending = turn.userMessage?.isPending == true ? " (pending)" : ""
    let segments = turn.segments.map { segment -> String in
        switch segment {
        case .work(let g): "work(\(g.thoughtCount)t,\(g.toolCallCount)c\(g.isActive ? ",live" : ""))"
        case .prose(let r): if case .assistantMessage(let m) = r.item { "prose(\(m.text.count))" } else { "prose" }
        case .todo: "todo"
        case .notice: "notice"
        }
    }.joined(separator: " ")
    return "turn id=\(turn.id) phase=\(turn.phase) running=\(running) user=\"\(user)\"\(pending) [\(segments)]"
}
