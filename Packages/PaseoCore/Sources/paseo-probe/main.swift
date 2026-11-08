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
      workspaces               projects and workspaces from the live directory subscription
      checkout <workspaceId>   git status, PR badge and working diff summary
      files <workspaceId> [path]
                               list a directory in a workspace

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
