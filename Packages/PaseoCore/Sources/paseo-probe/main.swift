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
      agent-control [cwd]      full stack (AgentControlStore/ConversationStore) on a sandbox:
                               list providers, create an omp agent, switch its mode, answer a
                               permission request, rename and archive it (default cwd /tmp/fixture-sandbox)
      agent-config [cwd]       create a sandbox agent, then switch model, thinking and mode through
                               ConversationStore and print what the daemon reports afterwards
      open <agentId> [secs]    open a conversation the way the chat screen does, printing every
                               request type and latency and any errors for [secs] (default 10)
      host-settings [agentId]
                               host config, provider switches, slash commands, 15 s presence
                               heartbeat and push-token revocation (default: fixture sandbox agent)
      workspaces               projects and workspaces from the live directory subscription
      checkout <workspaceId>   git status, PR badge and working diff summary
      files <workspaceId> [path]
                               list a directory in a workspace
      schedules                full stack (SchedulesStore) on a sandbox schedule:
                               create, inspect, update, pause/resume, run once, logs and delete
      workspace-mutations      full stack on the sandbox workspace and a throwaway project:
                               pin, unpin, rename (incl. clear) and remove; reports archive-undo support
      git-extras [cwd]         full stack on /tmp/fixture-git: modern-vs-legacy diff,
                               branch suggestions/switch, discard, live file watch, PR badge
      upload <agentId> <localFile>
                               full stack: upload a tiny text file to the sandbox agent through
                               file.upload.request + binary frames, then ask it to print the
                               file's first line, showing the reply
      git-ops [cwd]            commits ahead of base + commit file diff (default /tmp/fixture-sandbox)
      fs-ops [cwd]             fs.entry create/rename/duplicate/delete + conflict-checked write
      attachments-search <agentId> [query]
                               full stack: search the conversation, list provider subagents and
                               send a message with a structured text attachment (default query
                               "ready")
      lifecycle                  create two throwaway agents in /tmp/fixture-sandbox, archive,
                               unarchive, rename and delete them, and list the history
      usage                        provider plan usage reports and the context meter: prints
                               report summaries plus the sandbox agent's context window usage
      rewind <agentId> [messageId scope]
                               rewind probe: prints server_info.features.rewind, the snapshot's
                               supportsRewind* flags and the rewindable user messages. Passing
                               <messageId scope> performs the rewind through the store
                               (conversation | files | both)

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
        // Daemons before 0.1.45 hide non-legacy providers (pi, omp) from clients that don't
        // identify a modern version. The app passes its own version; the probe passes this floor.
        appVersion: "0.1.45"
    )
}

/// Prints every request the store layer sends with its latency, so `open` can show what a chat
/// screen actually asks for and which request fails. Delegates everything to the real connection.
final class LoggingDaemonClient: DaemonClient, @unchecked Sendable {
    private let inner: any DaemonClient

    init(_ inner: any DaemonClient) { self.inner = inner }

    func send<R: PaseoRequest>(_ request: R, timeout: Duration) async throws -> R.Response {
        let started = Date()
        do {
            let response = try await inner.send(request, timeout: timeout)
            print("  req \(R.type) \(milliseconds(since: started)) ok")
            return response
        } catch {
            print("  req \(R.type) \(milliseconds(since: started)) FAILED \(error)")
            throw error
        }
    }

    func initiate<R: PaseoRequest>(_ request: R, timeout: Duration) async throws -> InitiatedResponse<R> {
        let started = Date()
        do {
            let initiated = try await inner.initiate(request, timeout: timeout)
            print("  req \(R.type) \(milliseconds(since: started)) ok")
            return initiated
        } catch {
            print("  req \(R.type) \(milliseconds(since: started)) FAILED \(error)")
            throw error
        }
    }

    func send<M: PaseoOutboundMessage>(_ message: M) async throws {
        let started = Date()
        do {
            try await inner.send(message)
            print("  msg \(M.type) \(milliseconds(since: started))")
        } catch {
            print("  msg \(M.type) \(milliseconds(since: started)) FAILED \(error)")
            throw error
        }
    }

    func send(binary: Data) async throws {
        let started = Date()
        do {
            try await inner.send(binary: binary)
            print("  bin ✓ \(binary.count)B \(milliseconds(since: started))")
        } catch {
            print("  bin ✗ \(binary.count)B \(milliseconds(since: started)) FAILED \(error)")
            throw error
        }
    }

    var events: AsyncStream<DaemonEvent> { inner.events }
    var states: AsyncStream<ConnectionState> { inner.states }

    private func milliseconds(since date: Date) -> String {
        "\(Int(Date().timeIntervalSince(date) * 1000))ms"
    }
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
    case .usageUpdated: "usage_updated"
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
    print("ownedSubscriptions: feature=\(info.hasFeature(OwnedSubscriptions.feature)) client=\(OwnedSubscriptions.isEnabled) modern=\(info.supportsOwnedSubscriptions)")
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
    case "agent-control":
        try await runAgentControl(connection, cwd: arguments.commandArguments.first ?? "/tmp/fixture-sandbox")
    case "agent-config":
        try await runAgentConfig(connection, cwd: arguments.commandArguments.first ?? "/tmp/fixture-sandbox")
    case "open":
        guard let agentId = arguments.commandArguments.first else {
            throw ProbeError("open needs an <agentId>")
        }
        let seconds = arguments.commandArguments.count > 1 ? Int(arguments.commandArguments[1]) ?? 10 : 10
        try await runOpen(connection, agentId: agentId, seconds: seconds)
    case "host-settings":
        try await runHostSettings(
            connection,
            agentId: arguments.commandArguments.first
                ?? "1c51ee58-765c-4f8d-bf27-7009338b361e")
    case "workspaces":
        try await runWorkspaces(connection)
    case "checkout":
        guard let workspaceId = arguments.commandArguments.first else {
            throw ProbeError("checkout needs a <workspaceId>")
        }
        try await runCheckout(connection, workspaceId: workspaceId)
    case "files":
        guard let workspaceId = arguments.commandArguments.first else {
            throw ProbeError("files needs a <workspaceId>")
        }
        try await runFiles(connection, workspaceId: workspaceId, path: arguments.commandArguments.dropFirst().first)
    case "schedules":
        try await runSchedules(connection)
    case "workspace-mutations":
        try await runWorkspaceMutations(connection)
    case "git-extras":
        try await runGitExtras(
            connection, cwd: arguments.commandArguments.first ?? "/tmp/fixture-git/scratch-repo")
    case "upload":
        guard let agentId = arguments.commandArguments.first else {
            throw ProbeError("upload needs an <agentId> <localFile>")
        }
        guard let path = arguments.commandArguments.dropFirst().first else {
            throw ProbeError("upload needs an <agentId> <localFile>")
        }
        try await runUpload(connection, agentId: agentId, path: path)
    case "git-ops":
        try await runGitOps(connection, cwd: arguments.commandArguments.first ?? "/tmp/fixture-sandbox")
    case "fs-ops":
        try await runFsOps(connection, cwd: arguments.commandArguments.first ?? "/tmp/fixture-sandbox")
    case "setup":
        try await runSetupObservation(connection, cwd: arguments.commandArguments.first ?? "/tmp/fixture-sandbox")
    case "project-config":
        try await runProjectConfig(connection, repoRoot: arguments.commandArguments.first ?? "/tmp/fixture-sandbox")
    case "usage":
        try await runUsage(connection)
    case "attachments-search":
        guard let agentId = arguments.commandArguments.first else {
            throw ProbeError("attachments-search needs an <agentId>")
        }
        let query = arguments.commandArguments.dropFirst().first ?? "ready"
        try await runAttachmentsSearch(connection, agentId: agentId, query: query)
    case "rewind":
        guard let agentId = arguments.commandArguments.first else {
            throw ProbeError("rewind needs an <agentId>")
        }
        let rest = Array(arguments.commandArguments.dropFirst())
        if rest.count == 2 {
            try await runRewind(connection, agentId: agentId, messageId: rest[0], scope: rest[1])
        } else {
            try await runRewind(connection, agentId: agentId, messageId: nil, scope: nil)
        }
    case "lifecycle":
        try await runLifecycle(connection, cwd: arguments.commandArguments.first ?? "/tmp/fixture-sandbox")
    default:
        throw ProbeError("unknown command \(arguments.command)\n\n\(usage)")
    }

    connection.disconnect()
} catch {
    FileHandle.standardError.write(Data("paseo-probe: \(error)\n".utf8))
    exit(1)
}

/// Agent history incl. archived, rename/archive/unarchive/delete — only agents created here, in the sandbox.
@MainActor
func runLifecycle(_ connection: DaemonConnection, cwd: String) async throws {
    let sandbox = "/tmp/fixture-sandbox"
    guard cwd == sandbox else {
        throw ProbeError("lifecycle only runs in \(sandbox); refusing to create agents in \(cwd)")
    }
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    await session.agentControl.loadCatalog(cwd: sandbox)
    guard session.agentControl.phase == .ready else {
        throw ProbeError("provider catalogue failed: \(session.agentControl.phase)")
    }
    let provider = "omp"
    let models = session.agentControl.models(forProvider: provider)
    guard let model = models.first?.id else { throw ProbeError("\(provider) reports no models") }

    var created: [String] = []
    do {
        for title in ["M7e fixture A", "M7e fixture B"] {
            guard
                let agentId = await session.agentControl.createAgent(
                    cwd: sandbox, provider: provider, model: model, modeId: "full",
                    prompt: "Reply with the single word: ready", title: title)
            else {
                throw ProbeError("create failed: \(session.agentControl.actionError ?? "unknown error")")
            }
            created.append(agentId)
            print("created \(String(agentId.prefix(8))) (\(title))")
        }

        // Wait for both first turns to finish, so refresh can resume the provider session.
        for agentId in created {
            let store = session.conversation(for: agentId)
            try await waitUntil("first turn for \(agentId)", timeout: 120) { !store.isRunning }
            print("settled: \(String(agentId.prefix(8)))")
        }

        let lifecycle = session.agentLifecycle
        await lifecycle.load()
        let ownAfterCreate = lifecycle.entries.filter { created.contains($0.id) }
        print("history entries (own): \(ownAfterCreate.count) phase=\(lifecycle.phase)")

        for agentId in created {
            let archived = await lifecycle.archive(agentId: agentId)
            print("archive \(String(agentId.prefix(8))) -> \(archived)")
        }
        let archivedA = lifecycle.entries.first { $0.id == created[0] }?.archivedAt
        print("archivedAt set on A: \(archivedA != nil)")

        let unarchived = await lifecycle.unarchive(agentId: created[0])
        print("unarchive \(String(created[0].prefix(8))) -> \(unarchived)")
        let clearedA = lifecycle.entries.first { $0.id == created[0] }?.archivedAt == nil
        print("archivedAt cleared on A: \(clearedA)")

        for agentId in created {
            let renamed = await lifecycle.rename(agentId: agentId, to: "M7e fixture renamed")
            print("rename \(String(agentId.prefix(8))) -> \(renamed)")
        }

        for agentId in created {
            let deleted = await lifecycle.delete(agentId: agentId)
            print("delete \(String(agentId.prefix(8))) -> \(deleted)")
        }

        await lifecycle.load()
        let remaining = lifecycle.entries.filter { created.contains($0.id) }
        print("own entries remaining after cleanup: \(remaining.count)")
        guard remaining.isEmpty, lifecycle.phase == .ready else {
            throw ProbeError("cleanup failed or history not ready")
        }
        print("OK")
    } catch {
        for agentId in created { _ = await session.agentLifecycle.delete(agentId: agentId) }
        throw error
    }
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

    // The directory's owned subscription id arrives with the first terminals_changed snapshot.
    let directoryDeadline = Date().addingTimeInterval(2)
    while store.directorySubscriptionId(for: workspaceId) == nil, Date() < directoryDeadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    print("directory subscription: \(store.directorySubscriptionId(for: workspaceId) ?? "none (legacy)")")

    let terminal = await store.createTerminal(in: workspaceId, cwd: cwd, name: "paseo-probe")
    guard let terminal else { throw ProbeError("create terminal failed: \(store.error ?? "unknown")") }
    print("created \(terminal.id) name=\(terminal.name) cwd=\(terminal.cwd ?? "-")")

    let stream = await store.attach(terminal.id, size: TerminalSize(rows: 24, cols: 80))
    print("stream subscription: \(store.subscriptionId(forTerminal: terminal.id) ?? "none (legacy)")")
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
    print("stream subscription after detach: \(store.subscriptionId(forTerminal: terminal.id) ?? "released")")
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

@MainActor
func waitUntil(
    _ label: String, timeout: TimeInterval = 60, _ condition: @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(100))
    }
    if condition() { return }
    throw ProbeError("timed out waiting for \(label)")
}

func modeText(_ agent: AgentSnapshot?) -> String {
    agent?.currentModeId ?? "-"
}

/// Mimics the app's chat screen opening: connect, start the session, open the conversation and
/// watch it settle. Every request and its latency is logged, so a wrongly encoded request (the
/// daemon rejects it, nobody answers, the caller times out) is visible in one run.
@MainActor
func runOpen(_ connection: DaemonConnection, agentId: String, seconds: Int) async throws {
    try await connection.connect()
    let session = HostSession(client: LoggingDaemonClient(connection))
    await session.start()
    print("opening \(String(agentId.prefix(8)))")
    let store = session.conversation(for: agentId)
    try await waitUntil("the conversation to load", timeout: 20) { store.phase != .loading }
    print(
        "loaded: phase=\(store.phase) rows=\(store.timeline.rows.count) turns=\(store.turns.count)"
            + " actionError=\(store.actionError ?? "none") backgroundError=\(store.backgroundError ?? "none")"
    )

    var last = ""
    let deadline = Date().addingTimeInterval(Double(seconds))
    while Date() < deadline {
        let line =
            "running=\(store.isRunning) actionError=\(store.actionError ?? "none")"
            + " backgroundError=\(store.backgroundError ?? "none")"
        if line != last {
            print("  \(line)")
            last = line
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    session.closeConversation(agentId)
}

/// Verifies that model, thinking and mode switches reach the daemon: each change goes through
/// `ConversationStore`, then the agent snapshot is fetched again from the daemon and printed.
/// Only ever creates an agent in the sandbox cwd, and archives it.
@MainActor
func runAgentConfig(_ connection: DaemonConnection, cwd: String) async throws {
    let sandbox = "/tmp/fixture-sandbox"
    guard cwd == sandbox else {
        throw ProbeError("agent-config only runs in \(sandbox); refusing to create an agent in \(cwd)")
    }

    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    await session.agentControl.loadCatalog(cwd: sandbox)
    guard session.agentControl.phase == .ready else {
        throw ProbeError("provider catalogue failed: \(session.agentControl.phase)")
    }

    let provider = "omp"
    let models = session.agentControl.models(forProvider: provider)
    let modes = session.agentControl.modes(forProvider: provider).map(\.id)
    guard let firstModel = models.first?.id else { throw ProbeError("\(provider) reports no models") }
    guard
        let agentId = await session.agentControl.createAgent(
            cwd: sandbox, provider: provider, model: firstModel, modeId: modes.first,
            prompt: "Reply with the single word: ready", title: "M2.5a config probe")
    else {
        throw ProbeError("create failed: \(session.agentControl.actionError ?? "unknown error")")
    }
    print("created \(String(agentId.prefix(8))) model=\(firstModel)")
    var archived = false

    do {
        let store = session.conversation(for: agentId)
        try await waitUntil("the conversation to load") { store.phase == .ready }
        try await waitUntil("the first turn to finish", timeout: 120) { !store.isRunning }
        print(
            "start: store model=\(store.agent?.model ?? "-") thinking=\(store.agent?.effectiveThinkingOptionId ?? "-")"
                + " mode=\(store.agent?.currentModeId ?? "-")"
        )

        if let nextModel = models.first(where: { $0.id != firstModel && $0.isSelectable != false })?.id {
            await store.setModel(nextModel)
            try await waitUntil("the model switch", timeout: 20) { store.agent?.model == nextModel }
            if let daemon = try await daemonAgent(connection, id: agentId) {
                print(
                    "model -> \(nextModel): store=\(store.agent?.model ?? "-") daemon=\(daemon.model ?? "-")"
                        + " actionError=\(store.actionError ?? "none")"
                )
            }
        }

        let thinking =
            models.first { $0.id == (store.agent?.model ?? firstModel) }?.thinkingOptions ?? []
        if let option = thinking.first(where: { $0.id != store.agent?.effectiveThinkingOptionId })?.id {
            await store.setThinking(option)
            try await waitUntil("the thinking switch", timeout: 20) {
                store.agent?.effectiveThinkingOptionId == option
            }
            if let daemon = try await daemonAgent(connection, id: agentId) {
                print(
                    "thinking -> \(option): store=\(store.agent?.effectiveThinkingOptionId ?? "-")"
                        + " daemon=\(daemon.effectiveThinkingOptionId ?? "-")"
                        + " actionError=\(store.actionError ?? "none")"
                )
            }
        }

        if let mode = modes.first(where: { $0 != store.agent?.currentModeId }) {
            await store.setMode(mode)
            try await waitUntil("the mode switch", timeout: 20) { store.agent?.currentModeId == mode }
            if let daemon = try await daemonAgent(connection, id: agentId) {
                print(
                    "mode -> \(mode): store=\(store.agent?.currentModeId ?? "-")"
                        + " daemon=\(daemon.currentModeId ?? "-")"
                        + " actionError=\(store.actionError ?? "none")"
                )
            }
        }

        await store.archive()
        archived = true
        try await waitUntil("the agent to leave the list", timeout: 30) {
            !session.agents.contains { $0.id == agentId }
        }
        print("archived; agents listed now: \(session.agents.count)")
        session.closeConversation(agentId)
    } catch {
        if !archived {
            _ = try? await connection.send(ArchiveAgentRequest(agentId: agentId))
            print("cleanup: archived \(String(agentId.prefix(8))) after failure")
        }
        throw error
    }
}

/// The daemon's own view of one agent, bypassing every store cache.
func daemonAgent(_ connection: DaemonConnection, id: String) async throws -> AgentSnapshot? {
    let response = try await connection.send(FetchAgentsRequest(page: .init(limit: 200)))
    return response.entries.first { $0.agent.id == id }?.agent
}

/// End-to-end check of T6 against the live daemon: catalogue, create, mode switch, permission
/// answer, rename, archive. Only ever creates an agent in the given sandbox cwd, and archives it.
@MainActor
func runAgentControl(_ connection: DaemonConnection, cwd: String) async throws {
    let sandbox = "/tmp/fixture-sandbox"
    guard cwd == sandbox else {
        throw ProbeError("agent-control only runs in \(sandbox); refusing to create an agent in \(cwd)")
    }

    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()

    let catalog = session.agentControl
    await catalog.loadCatalog(cwd: sandbox)
    guard catalog.phase == .ready else {
        throw ProbeError("provider catalogue failed: \(catalog.phase)")
    }
    let statuses = catalog.providers.map { entry in
        "\(entry.provider):\(entry.status)\(entry.enabled ? "" : "(disabled)")"
    }
    print("providers (\(catalog.providers.count)): \(statuses.joined(separator: " "))")
    for provider in catalog.readyProviders {
        let models = catalog.models(forProvider: provider.provider)
        let modes = catalog.modes(forProvider: provider.provider).map(\.id)
        print("  \(provider.provider): \(models.count) models, modes [\(modes.joined(separator: ","))]")
    }

    let provider = "omp"
    let model = "opencode-go/deepseek-v4.1-flash"
    let thinking = catalog.thinkingOptions(forProvider: provider, modelId: model).map(\.id)
    guard catalog.provider(provider)?.isAvailable == true else {
        throw ProbeError("\(provider) is not available in the catalogue")
    }
    print("\(provider) \(model) thinking: [\(thinking.joined(separator: ","))]")

    guard
        let agentId = await catalog.createAgent(
            cwd: sandbox, provider: provider, model: model, modeId: "full",
            prompt: "Reply with the single word: ready", title: "T6 probe")
    else {
        throw ProbeError("create failed: \(catalog.actionError ?? "unknown error")")
    }
    print("created \(String(agentId.prefix(8))) in \(sandbox) mode=full")
    var archived = false

    do {
        let store = session.conversation(for: agentId)
        try await waitUntil("the conversation to load") { store.phase == .ready }
        try await waitUntil("the first turn to finish", timeout: 120) { !store.isRunning }
        print("agent idle: mode=\(modeText(store.agent)) model=\(store.agent?.model ?? "-")")

        await store.setMode("ask")
        try await waitUntil("the mode switch") { store.agent?.currentModeId == "ask" }
        print("mode -> ask: accepted, notice=\(store.lastNotice?.message ?? "none")")

        await store.send("Use the shell tool to run exactly: echo t6-probe-permission")
        try await waitUntil("a permission request", timeout: 120) { !store.pendingPermissions.isEmpty }
        guard let request = store.pendingPermissions.first else {
            throw ProbeError("permission request vanished before it could be answered")
        }
        let options = (request.actions ?? []).map { "\($0.id):\($0.behavior)" }.joined(separator: ",")
        print("permission: kind=\(request.kind) name=\(request.name) actions=[\(options)]")
        print("  title: \(request.title?.replacingOccurrences(of: "\n", with: " / ") ?? "-")")

        await store.respond(to: request.id, with: .allowing())
        try await waitUntil("the permission resolution", timeout: 60) { store.pendingPermissions.isEmpty }
        print("answered allow; pending=\(store.pendingPermissions.count)")

        await store.rename(to: "T6 probe agent")
        try await waitUntil("the rename") { store.agent?.title == "T6 probe agent" }
        print("renamed: title=\(store.agent?.title ?? "-")")

        await store.archive()
        archived = true
        try await waitUntil("the agent to leave the list", timeout: 30) {
            !session.agents.contains { $0.id == agentId }
        }
        print("archived; agents listed now: \(session.agents.count)")
        session.closeConversation(agentId)
    } catch {
        // Never leave a sandbox agent behind.
        if !archived {
            _ = try? await connection.send(ArchiveAgentRequest(agentId: agentId))
            print("cleanup: archived \(String(agentId.prefix(8))) after failure")
        }
        throw error
    }
}

/// End-to-end check of T10 against the live daemon: config read, a harmless patch that is restored,
/// slash commands for the sandbox agent, presence heartbeats and push-token revocation.
@MainActor
func runHostSettings(_ connection: DaemonConnection, agentId: String) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    let store = session.hostSettings

    await store.load()
    guard store.phase == .ready else {
        throw ProbeError("daemon config failed to load: \(store.phase)")
    }
    let config = try unwrapConfig(store)
    let enabledProviders = config.providers
        .filter { $0.value.enabled != false }
        .keys.sorted()
    let enabledList = enabledProviders.joined(separator: ",")
    print(
        "config: providers=\(config.providers.count) enabled=[\(enabledList)] profiles=\(store.profiles.count)"
    )
    print(
        "features: agentProfiles=\(store.supportsProfiles) pushTokenRevocation=\(store.supportsPushTokenRevocation)"
    )
    let inject = config.mcp?.injectIntoAgents.map(String.init) ?? "-"
    let cleanup = config.idleRuntimeCleanup.map(String.init) ?? "-"
    print(
        "settings: mcp.injectIntoAgents=\(inject) "
            + "autoArchiveAfterMerge=\(config.autoArchiveAfterMerge) idleRuntimeCleanup=\(cleanup)"
    )

    let commands = await store.loadCommands(for: agentId)
    let kinds = Dictionary(grouping: commands, by: { command -> String in
        switch command.kind {
        case .command: "command"
        case .skill: "skill"
        case .unknown(let raw): raw
        }
    }).mapValues(\.count)
    let kindText = kinds.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    print("commands for \(String(agentId.prefix(8))): \(commands.count) [\(kindText)]")
    print("  first: \(commands.prefix(4).map(\.name).joined(separator: ", "))")
    if let error = store.commandError(for: agentId) { print("  commandsError: \(error)") }

    store.startPresence(focusedAgentId: agentId, appVisible: true)
    try await Task.sleep(for: .milliseconds(200))
    print("presence: started focus=\(String(agentId.prefix(8))) sent=\(store.presenceSentCount)")
    store.updateVisibility(false)
    try await Task.sleep(for: .milliseconds(200))
    print("presence: hidden sent=\(store.presenceSentCount) visible=\(store.appVisible)")
    try await Task.sleep(for: .seconds(16))
    print("presence: after 16 s sent=\(store.presenceSentCount) (15 s cadence expected)")
    store.stopPresence()

    let revoked = await store.unregisterPushToken("paseo-probe-not-registered")
    print("push revoke of an unregistered token: success=\(revoked) error=\(store.error ?? "none")")

    guard let originalPrompt = config.resumePrompt else {
        throw ProbeError("config.resumePrompt is missing; not writing config")
    }
    var patch = DaemonConfigPatch()
    patch.resumePrompt = "\(originalPrompt) [probe]"
    let patched = await store.save(patch)
    let patchedPrompt = store.config?.resumePrompt ?? "-"
    print(
        "patch resumePrompt: saved=\(patched) effective=\(patchedPrompt) error=\(store.error ?? "none")"
    )
    var restore = DaemonConfigPatch()
    restore.resumePrompt = originalPrompt
    let restored = await store.save(restore)
    let restoredPrompt = store.config?.resumePrompt ?? "-"
    print(
        "restore resumePrompt: saved=\(restored) effective=\(restoredPrompt) error=\(store.error ?? "none")"
    )
    guard restored, store.config?.resumePrompt == originalPrompt else {
        throw ProbeError("daemon config was not restored")
    }
}

/// Reads the config the store holds, or fails the probe instead of force-unwrapping.
@MainActor
func unwrapConfig(_ store: HostSettingsStore) throws -> DaemonConfig {
    guard let config = store.config else { throw ProbeError("daemon config is nil") }
    return config
}

// MARK: - Workspaces and git

func workspaceKindText(_ kind: WorkspaceKind) -> String {
    switch kind {
    case .directory: "directory"
    case .localCheckout: "local_checkout"
    case .checkout: "checkout"
    case .worktree: "worktree"
    case .unknown(let raw): raw
    }
}

func projectKindText(_ kind: WorkspaceProjectKind) -> String {
    switch kind {
    case .git: "git"
    case .nonGit: "non_git"
    case .directory: "directory"
    case .unknown(let raw): raw
    }
}

func bucketText(_ status: WorkspaceStatusBucket) -> String {
    switch status {
    case .needsInput: "needs_input"
    case .failed: "failed"
    case .running: "running"
    case .attention: "attention"
    case .done: "done"
    case .unknown(let raw): raw
    }
}

func mergeableText(_ value: CheckoutMergeable) -> String {
    switch value {
    case .mergeable: "MERGEABLE"
    case .conflicting: "CONFLICTING"
    case .unknownState: "UNKNOWN"
    case .unknown(let raw): raw
    }
}

@MainActor
func waitForDirectory(_ session: HostSession, seconds: Int = 15) async -> Bool {
    let deadline = Date().addingTimeInterval(Double(seconds))
    while Date() < deadline {
        if session.workspaceDirectory.hasLoaded { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return session.workspaceDirectory.hasLoaded
}

@MainActor
func waitForCheckout(_ store: CheckoutStore, seconds: Int = 15) async -> Bool {
    let deadline = Date().addingTimeInterval(Double(seconds))
    while Date() < deadline {
        if store.phase != .loading, store.diffPhase != .loading { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return false
}

@MainActor
func runWorkspaces(_ connection: DaemonConnection) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    guard await waitForDirectory(session) else {
        throw ProbeError("workspace directory did not load: \(session.workspaceDirectory.error ?? "unknown error")")
    }
    let directory = session.workspaceDirectory
    print("projects: \(directory.projects.count)  workspaces: \(directory.workspaces.count)")
    for group in directory.groups {
        let project = group.project
        print("project \(project.projectId)  \(project.projectDisplayName)  [\(projectKindText(project.projectKind))]  \(project.projectRootPath)")
        for workspace in group.workspaces {
            let branch = workspace.branch ?? "-"
            let dirty = workspace.isDirty ? "dirty" : "clean"
            let stat = workspace.diffStat.map { "+\($0.additions)-\($0.deletions)" } ?? "-"
            let scripts = workspace.scripts.isEmpty ? "-" : workspace.scripts.map(\.scriptName).joined(separator: ",")
            let pinned = workspace.isPinned ? " pinned" : ""
            print("  \(workspace.id)  \(workspaceKindText(workspace.workspaceKind))  \(bucketText(workspace.status))\(pinned)  \(workspace.name)  branch=\(branch)  \(dirty)  \(stat)  scripts=\(scripts)")
            print("    cwd=\(workspace.cwd)")
        }
    }
    if let error = directory.error { print("error: \(error)") }
}

@MainActor
func runCheckout(_ connection: DaemonConnection, workspaceId: String) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    guard await waitForDirectory(session) else {
        throw ProbeError("workspace directory did not load")
    }
    guard let workspace = session.workspaceDirectory.workspace(id: workspaceId) else {
        throw ProbeError("unknown workspace \(workspaceId)")
    }
    let store = session.checkout(for: workspace)
    _ = await waitForCheckout(store)

    print("workspace \(workspace.id)  \(workspace.name)  cwd=\(store.cwd)")
    if let status = store.status {
        let ahead = status.aheadBehind.map { "+\($0.ahead)/-\($0.behind)" } ?? "-"
        print("status isGit=\(status.isGit) branch=\(status.currentBranch ?? "-") dirty=\(status.isDirty.map(String.init) ?? "-") aheadBehind=\(ahead) upstream=\(status.upstreamRef ?? "-") remote=\(status.remoteUrl ?? "-")")
        print("base=\(status.baseRef ?? "-") comparisonBase=\(status.comparisonBaseRef ?? "-")")
    } else {
        print("status: \(store.statusError ?? "unavailable")")
    }
    if let pr = store.prStatus {
        print("pr #\(pr.number.map(String.init) ?? "-") \(pr.state) \(pr.title) mergeable=\(mergeableText(pr.mergeable)) checks=\(pr.checksStatus ?? "-")")
    } else {
        print("pr: \(store.prStatusError ?? "none")")
    }
    if let diff = store.diff {
        print("diff \(diff.files.count) files +\(diff.additions)-\(diff.deletions) tooLarge=\(diff.isTooLarge)")
        for file in diff.files {
            let flag = file.isNew ? "new" : (file.isDeleted ? "deleted" : "modified")
            print("  \(flag)  +\(file.additions)-\(file.deletions)  \(file.path)")
        }
    } else {
        print("diff: \(store.diffError ?? "none")")
    }
    if let error = store.actionError { print("actionError: \(error)") }
    await session.closeCheckout(workspaceId)
}

@MainActor
func runFiles(_ connection: DaemonConnection, workspaceId: String, path: String?) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    guard await waitForDirectory(session) else {
        throw ProbeError("workspace directory did not load")
    }
    guard let workspace = session.workspaceDirectory.workspace(id: workspaceId) else {
        throw ProbeError("unknown workspace \(workspaceId)")
    }
    let store = session.checkout(for: workspace)
    await store.files.list(path)
    print("workspace \(workspace.id)  cwd=\(store.cwd)  path=\(store.files.path ?? path ?? ".")  entries=\(store.files.entries.count)")
    for entry in store.files.entries {
        let kind = entry.isDirectory ? "dir " : "file"
        print("  \(kind)  \(entry.size)  \(entry.name)")
    }
    if let error = store.files.error { print("error: \(error)") }
    await session.closeCheckout(workspaceId)
}


// MARK: - Git extras (T11)

enum GitExtrasPhaseText {
    static func diff(_ phase: WorkspaceGitExtras.DiffPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .loading: return "loading"
        case .ready: return "ready"
        case .failed(let message): return "failed(\(message))"
        }
    }

    static func file(_ phase: WorkspaceGitExtras.FilePhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .loading: return "loading"
        case .ready: return "ready"
        case .failed(let message): return "failed(\(message))"
        }
    }
}

@discardableResult
func runGit(_ arguments: [String], cwd: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw ProbeError("git \(arguments.joined(separator: " ")) failed: \(output)")
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Creates the fixture repo idempotently: a bare remote and a checkout in /tmp/fixture-git only.
func ensureGitExtrasFixture(_ cwd: String) throws {
    let root = "/tmp/fixture-git"
    guard cwd == "\(root)/scratch-repo" else {
        throw ProbeError("git-extras only runs in \(root)/scratch-repo; refusing \(cwd)")
    }
    let remote = "\(root)/remote.git"
    let fileManager = FileManager.default
    try fileManager.createDirectory(atPath: remote, withIntermediateDirectories: true)
    if !fileManager.fileExists(atPath: "\(remote)/HEAD") {
        try runGit(["init", "--bare", "-q", "-b", "main", remote], cwd: root)
    }
    if !fileManager.fileExists(atPath: "\(cwd)/.git") {
        try fileManager.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        try runGit(["init", "-q", "-b", "main"], cwd: cwd)
        try runGit(["config", "user.email", "fixture@example.test"], cwd: cwd)
        try runGit(["config", "user.name", "Fixture"], cwd: cwd)
        try Data("# scratch\n\nline one\nline two\n".utf8)
            .write(to: URL(fileURLWithPath: "\(cwd)/README.md"))
        try Data("print(\"hello\")\n".utf8)
            .write(to: URL(fileURLWithPath: "\(cwd)/hello.py"))
        try runGit(["add", "."], cwd: cwd)
        try runGit(["commit", "-qm", "initial fixture commit"], cwd: cwd)
        try runGit(["remote", "add", "origin", remote], cwd: cwd)
        try runGit(["push", "-qu", "origin", "main"], cwd: cwd)
    }
    let branches = try runGit(["branch", "--list", "feature/t11"], cwd: cwd)
    if branches.isEmpty {
        try runGit(["checkout", "-qb", "feature/t11"], cwd: cwd)
        let readme = URL(fileURLWithPath: "\(cwd)/README.md")
        let existing = (try? String(contentsOf: readme, encoding: .utf8)) ?? "# scratch\n"
        try Data((existing + "feature line\n").utf8).write(to: readme)
        try runGit(["commit", "-qam", "feature commit"], cwd: cwd)
        try runGit(["push", "-qu", "origin", "feature/t11"], cwd: cwd)
    }
    try runGit(["checkout", "-q", "main"], cwd: cwd)
    try runGit(["reset", "-q", "--hard", "origin/main"], cwd: cwd)
}

/// End-to-end check of T11 against the live daemon. Only creates a workspace for the fixture repo
/// and archives it again; it never touches another workspace or project.
@MainActor
func runGitExtras(_ connection: DaemonConnection, cwd: String) async throws {
    try ensureGitExtrasFixture(cwd)
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    guard await waitForDirectory(session) else {
        throw ProbeError("workspace directory did not load: \(session.workspaceDirectory.error ?? "unknown error")")
    }

    let projectsBefore = (try? await connection.send(ProjectListRequest()))?.projects
        .filter { $0.projectRootPath == cwd } ?? []
    var workspace = session.workspaceDirectory.workspaces.first { $0.cwd == cwd }
    var createdWorkspace = false
    if workspace == nil {
        let response = try await connection.send(
            WorkspaceCreateRequest(
                source: .directory(path: cwd, projectId: nil),
                idempotencyKey: "paseo-probe-t11-\(UUID().uuidString)"))
        guard let created = response.workspace else {
            throw ProbeError("workspace.create failed: \(response.error ?? "unknown")")
        }
        workspace = created
        createdWorkspace = true
    }
    guard let workspace else { throw ProbeError("no workspace for \(cwd)") }

    var cleanedUp = false
    do {
        let checkout = session.checkout(for: workspace)
        _ = await waitForCheckout(checkout)
        try await waitUntil("the initial checkout diff", timeout: 30) {
            checkout.diffPhase != .idle && checkout.diffPhase != .loading
        }
        let extras = session.gitExtras.workspace(for: checkout)
        let capabilities = extras.capabilities
        print(
            "workspace \(workspace.id) cwd=\(checkout.cwd) created=\(createdWorkspace) "
                + "modernDiff=\(capabilities.supportsModernDiff) discard=\(capabilities.supportsDiscardChanges) "
                + "files=\(capabilities.supportsFileWatching)")

        await extras.loadBranchSuggestions(query: "feature", limit: 20)
        print("branches: \(extras.branchSuggestions.map(\.name).joined(separator: ","))")

        let switched = await extras.switchBranch("feature/t11")
        print("switch feature/t11 -> \(switched) branch=\(extras.currentBranch ?? "-")")
        let switchedBack = await extras.switchBranch("main")
        print("switch main -> \(switchedBack) branch=\(extras.currentBranch ?? "-")")

        let readme = URL(fileURLWithPath: "\(cwd)/README.md")
        let original = try Data(contentsOf: readme)
        try (original + Data("probe diff\n".utf8)).write(to: readme)
        // The daemon's git observer debounces stat changes before the diff snapshot catches up.
        try await Task.sleep(for: .seconds(1))

        await extras.loadDiff(compare: .working(cwd: cwd))
        try await waitUntil("the diff", timeout: 30) { extras.diffPhase != .loading }
        print(
            "diff pipeline=\(extras.isUsingLegacyPipeline ? "legacy" : "modern") "
                + "phase=\(GitExtrasPhaseText.diff(extras.diffPhase)) files=\(extras.filesChanged) "
                + "+\(extras.additions)-\(extras.deletions)")
        for file in extras.files.prefix(5) {
            print("  \(file.path) +\(file.additions)-\(file.deletions)")
        }

        let discarded = await extras.discard(paths: ["README.md"])
        print("discard -> \(discarded) dirty=\(checkout.status?.isDirty.map(String.init) ?? "-")")
        try original.write(to: readme)

        await extras.watchFile("README.md")
        let initialSize = extras.watchedFile?.size
        print(
            "file \(extras.watchedFile?.path ?? "-") phase=\(GitExtrasPhaseText.file(extras.filePhase)) "
                + "size=\(initialSize.map(String.init) ?? "-")")

        try (original + Data("probe watched\n".utf8)).write(to: readme)
        _ = await eventuallyProbe(timeout: 5) {
            extras.watchedFile?.size != initialSize && extras.watchedFile?.size != nil
        }
        print("file update size=\(extras.watchedFile?.size.map(String.init) ?? "-")")
        try original.write(to: readme)
        await extras.stopWatchingFile()

        await extras.loadPrStatus()
        let badge = extras.prBadge
        print(
            "pr auth=\(extras.prAuthState.map { String(describing: $0) } ?? "-") "
                + "badge=\(badge.map { " #\($0.number.map(String.init) ?? "-") \($0.state) checks=\($0.checks)" } ?? extras.prError ?? "none")")

        if let error = extras.actionError ?? extras.diffError ?? extras.fileError {
            print("error: \(error)")
        }

        await session.closeCheckout(workspace.id)
        if createdWorkspace {
            _ = try? await connection.send(ArchiveWorkspaceRequest(workspaceId: workspace.id))
            if projectsBefore.isEmpty {
                let projects = (try? await connection.send(ProjectListRequest()))?.projects ?? []
                if let project = projects.first(where: { $0.projectRootPath == cwd }) {
                    _ = try? await connection.send(
                        ProjectRemoveRequest(projectId: project.projectId))
                }
            }
            cleanedUp = true
        }
    } catch {
        await session.closeCheckout(workspace.id)
        if createdWorkspace, !cleanedUp {
            _ = try? await connection.send(ArchiveWorkspaceRequest(workspaceId: workspace.id))
            if projectsBefore.isEmpty {
                let projects = (try? await connection.send(ProjectListRequest()))?.projects ?? []
                if let project = projects.first(where: { $0.projectRootPath == cwd }) {
                    _ = try? await connection.send(
                        ProjectRemoveRequest(projectId: project.projectId))
                }
            }
        }
        throw error
    }
}

@MainActor
func eventuallyProbe(timeout: TimeInterval, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return condition()
}

/// Read-only readout of the rewind capability and the rows an operator could rewind to;
/// with an explicit messageId and scope, performs one rewind through the conversation store.
@MainActor
func runRewind(_ connection: DaemonConnection, agentId: String, messageId: String?, scope: String?) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    let store = session.conversation(for: agentId)
    try await waitUntil("the conversation to load", timeout: 30) { store.phase == .ready }

    print("server features.rewind=\(session.isRewindSupportedByHost)")
    let caps = store.rewindCapabilities
    print("snapshot capabilities: conversation=\(caps.conversation) files=\(caps.files) both=\(caps.both) menu=\(caps.menu)")

    for row in store.timeline.rows {
        if case .userMessage(let message) = row.item {
            print("  seq=\(row.seqStart) role=user messageId=\(message.messageId ?? "-") clientMessageId=\(message.clientMessageId ?? "-")")
        }
    }

    if let messageId, let scope {
        let parsed: RewindScope
        switch scope {
        case "conversation": parsed = .conversation
        case "files": parsed = .files
        case "both": parsed = .both
        default:
            throw ProbeError("scope must be one of conversation, files or both")
        }
        print("rewinding to messageId=\(messageId) scope=\(scope)...")
        if let failure = await store.rewind(toMessageId: messageId, scope: parsed) {
            print("rewind refused: \(failure)")
        } else {
            print("rewind ok")
        }
    }
    session.closeConversation(agentId)
}

// MARK: - T12: attachments, search and subagents

@MainActor
func runAttachmentsSearch(_ connection: DaemonConnection, agentId: String, query: String) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    let store = session.conversation(for: agentId)
    try await waitUntil("the conversation to load", timeout: 30) { store.phase == .ready }

    print("agent \(String(agentId.prefix(8))) rows=\(store.timeline.rows.count) turns=\(store.turns.count)")
    print("provider subagents supported=\(store.subagents.isSupported)")

    await store.subagents.load()
    print("provider subagents=\(store.subagents.items.count) active=\(store.subagents.active.count) error=\(store.subagents.error ?? "none")")
    for subagent in store.subagents.items {
        let title = subagent.title ?? "-"
        print("  \(String(subagent.id.prefix(8))) \(subagent.provider) \(subagent.status) \(title)")
    }

    _ = await store.search.search(query)
    print("search query=\"\(query)\" epoch=\(store.search.epoch ?? "-") locations=\(store.search.locations.count) matches=\(store.search.matchCount) error=\(store.search.error ?? "none")")
    for location in store.search.locations.prefix(10) {
        print("  seq=\(location.seq) role=\(location.role) count=\(location.count ?? 1)")
    }

    let attachment = AgentAttachment.text(
        .init(text: "T12 probe attachment: hello from the sandbox.", title: "T12 probe"))
    await store.sendWithAttachments(
        "T12 probe: acknowledging the attached note.", attachments: [attachment])
    print("send actionError=\(store.actionError ?? "none") pending=\(store.timeline.rows.contains { $0.isPending })")
    session.closeConversation(agentId)
}

// MARK: - T14: file upload

@MainActor
func runUpload(_ connection: DaemonConnection, agentId: String, path: String) async throws {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else {
        throw ProbeError("cannot read file at \(path)")
    }
    let fileName = url.lastPathComponent
    let mimeType = mimeTypeForUpload(extension: url.pathExtension.lowercased())

    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    let store = session.conversation(for: agentId)
    try await waitUntil("the conversation to load", timeout: 30) { store.phase == .ready }

    print("uploading \(fileName) (\(data.count) bytes, \(mimeType)) to agent \(String(agentId.prefix(8)))")
    let file = await store.upload(data: data, fileName: fileName, mimeType: mimeType)
    guard let file else {
        throw ProbeError("upload failed: \(store.uploads.error ?? "unknown")")
    }
    print("uploaded id=\(file.id) fileName=\(file.fileName) size=\(file.size) path=\(file.path)")
    print("progress=\(store.uploads.progress) bytesSent=\(store.uploads.bytesSent)/\(store.uploads.totalBytes)")

    let prompt =
        "I uploaded a file to you at \(file.path). Print exactly its first line and nothing else."
    await store.sendWithAttachments(prompt, attachments: [.uploadedFile(file)])
    print("send actionError=\(store.actionError ?? "none") pending=\(store.timeline.rows.contains { $0.isPending })")

    var last = ""
    var sawRunning = false
    let deadline = Date().addingTimeInterval(240)
    while Date() < deadline {
        let line = describe(store.turns.last, running: store.isRunning)
        if line != last { print(line); last = line }
        if store.isRunning { sawRunning = true }
        if sawRunning, !store.isRunning { break }
        try await Task.sleep(for: .milliseconds(150))
    }
    print("final: turns=\(store.turns.count) running=\(store.isRunning)")
    if let turn = store.turns.last {
        for segment in turn.segments {
            if case .prose(let row) = segment, case .assistantMessage(let message) = row.item {
                print("reply: \(message.text)")
            }
        }
    }
    session.closeConversation(agentId)
}

func mimeTypeForUpload(extension ext: String) -> String {
    switch ext {
    case "txt": "text/plain"
    case "md": "text/markdown"
    case "json": "application/json"
    case "png": "image/png"
    case "jpg", "jpeg": "image/jpeg"
    case "pdf": "application/pdf"
    default: "application/octet-stream"
    }
}

// MARK: - Git ops and file ops (T15)

@MainActor
func runGitOps(_ connection: DaemonConnection, cwd: String) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    guard await waitForDirectory(session) else {
        throw ProbeError("workspace directory did not load: \(session.workspaceDirectory.error ?? "unknown error")")
    }
    guard let workspace = session.workspaceDirectory.workspaces.first(where: { $0.cwd == cwd }) else {
        throw ProbeError("no workspace for \(cwd); expected /tmp/fixture-sandbox to be registered")
    }
    let checkout = session.checkout(for: workspace)
    _ = await waitForCheckout(checkout)
    let actions = session.gitExtras.gitActions(for: checkout)
    print("workspace \(workspace.id) cwd=\(checkout.cwd) commitsList=\(actions.supportsCommitsList) baseClassification=\(actions.supportsCommitBaseClassification) forgeAutoMerge=\(actions.capabilities.forgeAutoMerge) legacyAutoMerge=\(actions.capabilities.legacyAutoMerge)")

    await actions.loadCommits()
    print("commits base=\(actions.commitsBaseRef ?? "-") count=\(actions.commits.count) error=\(actions.commitsError ?? "-")")
    for commit in actions.commits.prefix(5) {
        let files = commit.files.map { "\($0.path)(+\($0.additions)/-\($0.deletions))" }.joined(separator: ",")
        print("  \(commit.shortSha) \(commit.subject) [\(files)] isOnRemote=\(commit.isOnRemote) isOnBase=\(commit.isOnBase.map(String.init) ?? "-")")
    }

    if let first = actions.commits.first, let path = first.files.first?.path {
        let file = await actions.loadCommitFileDiff(sha: first.sha, path: path)
        if let file {
            print("file diff \(file.path): \(file.hunks.count) hunks +\(file.additions)-\(file.deletions) error=\(actions.commitFileDiffError ?? "-")")
        } else {
            print("file diff \(path): nil error=\(actions.commitFileDiffError ?? "-")")
        }
    }
    await session.closeCheckout(workspace.id)
}

/// File operations against the sandbox only. Creates `.t15-probe.txt`, writes it, renames it,
/// duplicates it, then deletes both copies. Never touches anything it didn't create.
@MainActor
func runFsOps(_ connection: DaemonConnection, cwd: String) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    guard await waitForDirectory(session) else {
        throw ProbeError("workspace directory did not load: \(session.workspaceDirectory.error ?? "unknown error")")
    }
    guard let workspace = session.workspaceDirectory.workspaces.first(where: { $0.cwd == cwd }) else {
        throw ProbeError("no workspace for \(cwd); expected /tmp/fixture-sandbox to be registered")
    }
    let checkout = session.checkout(for: workspace)
    _ = await waitForCheckout(checkout)
    let files = checkout.files
    print("workspace \(workspace.id) cwd=\(checkout.cwd) entryOps=\(files.supportsEntryOps) duplicate=\(files.supportsEntryDuplicate) editing=\(files.supportsFileEditing)")

    var created: [String] = []
    func attemptDelete(_ path: String, label: String) async {
        let ok = await files.delete(path: path)
        print("  delete \(path) -> \(ok) error=\(files.error ?? "-")")
        _ = label
    }

    let original = "t15-probe.txt"
    let renamed = "t15-probe-renamed.txt"
    let path = await files.createEntry(parentPath: nil, name: original, kind: .file)
    print("create -> \(path ?? "nil") error=\(files.error ?? "-")")
    if let path { created.append(path) }

    await files.read(path ?? original, maxBytes: 1024)
    let modifiedAt = files.file?.modifiedAt ?? ""
    let outcome = await files.write(
        path: path ?? original, content: "probe \(Date().timeIntervalSince1970)\n",
        expectedModifiedAt: modifiedAt)
    print("write -> \(fileWriteOutcomeText(outcome)) error=\(files.error ?? "-")")

    let renamedPath = await files.rename(path: path ?? original, to: renamed)
    print("rename -> \(renamedPath ?? "nil") error=\(files.error ?? "-")")
    if let renamedPath {
        created.removeAll { $0 == (path ?? original) }
        created.append(renamedPath)
    }

    let duplicatedPath = await files.duplicate(path: renamedPath ?? renamed)
    print("duplicate -> \(duplicatedPath ?? "nil") error=\(files.error ?? "-")")
    if let duplicatedPath { created.append(duplicatedPath) }

    for path in created { await attemptDelete(path, label: "cleanup") }

    await files.list()
    let leftover = files.entries.map(\.name).filter { $0.hasPrefix("t15-probe") }
    print("list after cleanup: entries=\(files.entries.count) leftover=\(leftover.isEmpty ? "none" : leftover.joined(separator: ","))")
    await session.closeCheckout(workspace.id)
}

func fileWriteOutcomeText(_ outcome: FileWriteOutcome) -> String {
    switch outcome {
    case .written(let modifiedAt, let size, let revision):
        return "written(size=\(size) revision=\(revision ?? "-") modifiedAt=\(modifiedAt))"
    case .conflict(let modifiedAt):
        return "conflict(currentModifiedAt=\(modifiedAt ?? "-"))"
    case .failed(let message):
        return "failed(\(message))"
    }
}

// MARK: - T16: provider usage reports and the context meter

@MainActor
func runUsage(_ connection: DaemonConnection) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()

    print("usage supported=\(session.hostUsage.isSupported)")
    let ok = await session.hostUsage.load(forceRefresh: true)
    print("usage load ok=\(ok) phase=\(session.hostUsage.phase) reports=\(session.hostUsage.reports.count)")
    if let error = session.hostUsage.error {
        print("usage error: \(error)")
    }
    for report in session.hostUsage.reports {
        let kind: String = {
            switch report.report {
            case .available(let available):
                let windows = available.windows.map { window in
                    let used = window.usedPct.map { "\($0)%" } ?? "-"
                    return "\(window.id)=\(used)"
                }.joined(separator: ", ")
                return "available plan=\(available.planLabel ?? "-") windows=[\(windows)]"
            case .unavailable(let problem):
                switch problem {
                case .expired(let expiresAt, _): return "unavailable expired expiresAt=\(expiresAt)"
                case .rejected(let status, _): return "unavailable rejected status=\(status)"
                case .noQuota(let detail): return "unavailable no_quota detail=\(detail)"
                case .unknown: return "unavailable unknown"
                }
            case .failure(let message):
                return "error \(message)"
            }
        }()
        print("  \(report.sourceId) (\(report.sourceLabel)): \(kind)")
    }

    let agentId = "1c51ee58-765c-4f8d-bf27-7009338b361e"
    let store = session.conversation(for: agentId)
    try await waitUntil("the conversation to load", timeout: 30) { store.phase == .ready }
    if let context = store.contextUsage {
        let percent = context.percentUsed.map { String(format: "%.1f", $0) } ?? "-"
        let used = context.usedTokens.map(String.init) ?? "-"
        let max = context.maxTokens.map(String.init) ?? "-"
        let cost = context.totalCostUsd.map { String(format: "%.4f", $0) } ?? "-"
        print("agent \(String(agentId.prefix(8))) context: used=\(used) / max=\(max) percent=\(percent) cost=$\(cost)")
    } else {
        print("agent \(String(agentId.prefix(8))) context: no usage reported")
    }
    session.closeConversation(agentId)
}

// MARK: - Setup observation (M2.10)

@MainActor
func runSetupObservation(_ connection: DaemonConnection, cwd: String) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    guard await waitForDirectory(session) else {
        throw ProbeError("workspace directory did not load: \(session.workspaceDirectory.error ?? "unknown error")")
    }
    guard let workspace = session.workspaceDirectory.workspaces.first(where: { $0.cwd == cwd }) else {
        throw ProbeError("no workspace for \(cwd)")
    }
    let store = session.setupObservation
    print("workspace \(workspace.id) observation=\(store.capabilities.observation) run=\(store.capabilities.run) owned=\(store.capabilities.ownedSubscriptions)")
    // `observe` uses the owned subscribe path when available and falls back to a status read.
    await store.observe(workspace.id)
    print("setup subscription: \(store.subscriptionId(for: workspace.id) ?? "none (polling)")")
    if let snapshot = store.snapshot(for: workspace.id) {
        print("status=\(snapshot.status) branch=\(snapshot.detail.branchName) logBytes=\(snapshot.detail.log.utf8.count) commands=\(snapshot.detail.commands.count)")
        if let error = snapshot.error { print("error=\(error)") }
        if let blocked = snapshot.blockedSource {
            print("blocked=\(blocked.forge) #\(blocked.number) repo=\(blocked.headRepository)")
        }
        for command in snapshot.detail.commands.prefix(5) {
            print("  [\(command.index)] \(command.command) status=\(command.status) exit=\(command.exitCode.map(String.init) ?? "-") ms=\(command.durationMs.map(String.init) ?? "-")")
        }
    } else {
        print("status=none (the workspace has no setup snapshot)")
    }
    await store.stopObserving(workspace.id)
}

// MARK: - Project config (M2.11)

@MainActor
func runProjectConfig(_ connection: DaemonConnection, repoRoot: String) async throws {
    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    _ = await waitForDirectory(session)
    await session.projectConfig.load(repoRoot: repoRoot)
    let store = session.projectConfig
    if let error = store.error {
        print("error=\(error.userMessage)")
        return
    }
    if let sendError = store.sendError {
        print("sendError=\(sendError)")
        return
    }
    print("phase=\(store.phase)")
    if let revision = store.revision {
        print("revision mtimeMs=\(revision.mtimeMs) size=\(revision.size)")
    } else {
        print("revision=none (no paseo.json)")
    }
    let (setup, teardown) = ProjectConfigEditor.worktreeCommands(store.config)
    print("setup=\(setup.joined(separator: "; "))")
    print("teardown=\(teardown.joined(separator: "; "))")
    for script in ProjectConfigEditor.scripts(store.config) {
        print("script \(script.name): \(script.command)")
    }
    if let project = session.workspaceDirectory.projects.first(where: { $0.projectRootPath == repoRoot }) {
        await session.projectIcons.load(projectId: project.projectId)
        print("icon bytes=\(session.projectIcons.iconData?.count ?? 0) mime=\(session.projectIcons.mimeType ?? "-")")
    } else {
        print("icon skipped (project not found for \(repoRoot))")
    }
}
