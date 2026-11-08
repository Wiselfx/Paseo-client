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
      workspaces               projects and workspaces from the live directory subscription
      checkout <workspaceId>   git status, PR badge and working diff summary
      files <workspaceId> [path]
                               list a directory in a workspace
      git-extras [cwd]         full stack on /tmp/fixture-git: modern-vs-legacy diff,
                               branch suggestions/switch, discard, live file watch, PR badge

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
    case "agent-control":
        try await runAgentControl(connection, cwd: arguments.commandArguments.first ?? "/tmp/fixture-sandbox")
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
    case "git-extras":
        try await runGitExtras(
            connection, cwd: arguments.commandArguments.first ?? "/tmp/fixture-git/scratch-repo")
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
