import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// What one attached terminal view receives. Marker cases bracket a replay so the renderer can
/// reset its emulator before the daemon's ANSI snapshot; `.output` is raw bytes either way.
public enum TerminalOutput: Sendable, Equatable {
    case replayBegin(TerminalReplayMetadata)
    case output(Data)
    case replayEnd
    /// The daemon detached this view. A non-nil error means observation failed and the process may
    /// still be running; nil means the stream ended cleanly (kill, PTY exit, workspace teardown).
    case exited(error: String?)
}

/// Live terminals and workspace scripts for every workspace the app has opened.
///
/// The terminal list is a full snapshot per workspace (`terminals_changed` replaces it wholesale).
/// Attachments are keyed by terminal id; binary frames are routed by the connection-local slot.
///
/// IMPLEMENTATION TICKET: docs/tickets/T8-terminals.md
@MainActor @Observable
public final class TerminalsStore {
    /// Server features that change how terminals and scripts are used. Read once per connection.
    public struct Capabilities: Sendable, Equatable {
        /// `terminal-restore-modes`: false means this host is too old to attach terminals safely.
        public var restoreModes = false
        /// `terminal-size-ownership`: claim/update resize intent.
        public var sizeOwnership = false
        /// `terminal-input-mode-replay`: replay preambles carry Kitty/Win32 input modes.
        public var inputModeReplay = false
        /// `terminal-grapheme-widths`: pick the renderer's grapheme width table from this.
        public var graphemeWidths = false
        /// `workspaceTerminals`: workspace-scoped terminal list/create convenience APIs.
        public var workspaceTerminals = false
        /// `terminalCollection`: directory subscriptions without a `cwd` are allowed.
        public var terminalCollection = false
        /// `workspaceScriptManagement`: script list/start/stop RPCs.
        public var workspaceScriptManagement = false

        public init(serverInfo: ServerInfo? = nil) {
            guard let serverInfo else { return }
            restoreModes = serverInfo.hasFeature("terminal-restore-modes")
            sizeOwnership = serverInfo.hasFeature("terminal-size-ownership")
            inputModeReplay = serverInfo.hasFeature("terminal-input-mode-replay")
            graphemeWidths = serverInfo.hasFeature("terminal-grapheme-widths")
            workspaceTerminals = serverInfo.hasFeature("workspaceTerminals")
            terminalCollection = serverInfo.hasFeature("terminalCollection")
            workspaceScriptManagement = serverInfo.hasFeature("workspaceScriptManagement")
        }
    }

    public private(set) var capabilities = Capabilities()
    /// Full terminal snapshot per workspace, newest state from `terminals_changed` or a list RPC.
    public private(set) var terminalsByWorkspace: [String: [TerminalInfo]] = [:]
    /// Configured scripts per workspace with lifecycle, health and proxy URLs.
    public private(set) var scriptsByWorkspace: [String: [WorkspaceScript]] = [:]
    public private(set) var loadingScriptWorkspaces: Set<String> = []
    /// Last terminal or script operation failure, for a transient banner. Cleared by a success.
    public internal(set) var error: String?

    /// `terminal-restore-modes` is mandatory for attaching; otherwise show the host-update UI.
    public var isSupported: Bool { capabilities.restoreModes }

    /// Internal (not private) so the M3g `TerminalRename` extension can send the rename RPC.
    internal let client: any DaemonClient
    private var watched: [String: WatchedWorkspace] = [:]
    private var attachments: [String: Attachment] = [:]
    private var slotTerminalIds: [UInt8: String] = [:]
    /// Server-assigned directory subscription id per workspace. Present only on modern sockets
    /// (the daemon tags `terminals_changed` with `subscriptionId`); nil on legacy ones.
    private var directorySubscriptionIds: [String: String] = [:]
    private var connectionState: ConnectionState = .idle
    private var wasConnected = false
    private var sawReconnect = false

    public init(client: any DaemonClient) {
        self.client = client
    }

    // MARK: Reading state

    public func terminals(in workspaceId: String) -> [TerminalInfo] {
        terminalsByWorkspace[workspaceId] ?? []
    }

    public func scripts(in workspaceId: String) -> [WorkspaceScript] {
        scriptsByWorkspace[workspaceId] ?? []
    }

    public func isAttached(_ terminalId: String) -> Bool {
        attachments[terminalId] != nil
    }

    /// The daemon's owned subscription id for a workspace's terminal directory, when this socket
    /// negotiated owned subscriptions. Nil on legacy sockets and before the first snapshot.
    public func directorySubscriptionId(for workspaceId: String) -> String? {
        directorySubscriptionIds[workspaceId]
    }

    /// The daemon's owned subscription id for one attached terminal, when owned subscriptions are
    /// in use. Nil on legacy sockets.
    public func subscriptionId(forTerminal terminalId: String) -> String? {
        attachments[terminalId]?.subscriptionId
    }

    /// The workspace whose list contains `terminalId`, when this store has seen that list.
    public func workspaceId(forTerminal terminalId: String) -> String? {
        terminalsByWorkspace.first { _, terminals in
            terminals.contains { $0.id == terminalId }
        }?.key
    }

    public func clearError() { error = nil }

    // MARK: Directory

    /// Starts the live terminal list for a workspace and loads terminals and scripts once.
    /// Safe to call again when the screen reappears.
    public func open(workspaceId: String, cwd: String? = nil) async {
        let previousCwd = watched[workspaceId]?.cwd
        watched[workspaceId] = WatchedWorkspace(cwd: cwd ?? previousCwd)
        if case .connected = connectionState {
            // A modern socket creates a new owned subscription per subscribe; drop the old one so
            // repeated screen appearances don't accumulate duplicate snapshots.
            if let previous = directorySubscriptionIds.removeValue(forKey: workspaceId) {
                await client.releaseOwnedSubscription(previous)
            }
            subscribeDirectory(workspaceId: workspaceId, cwd: watched[workspaceId]?.cwd)
            await refreshTerminals(in: workspaceId)
            // The view that asked for the directory went away (the panel closed): do not start
            // the scripts fetch, and do not repopulate a list the store's close already cleared.
            guard !Task.isCancelled else { return }
            await refreshScripts(in: workspaceId)
        }
    }

    /// Stops delivering directory updates and ends this workspace's terminal streams.
    public func close(workspaceId: String) {
        guard let workspace = watched.removeValue(forKey: workspaceId) else { return }
        let directorySubscriptionId = directorySubscriptionIds.removeValue(forKey: workspaceId)
        if case .connected = connectionState {
            if let directorySubscriptionId {
                releaseOwned(directorySubscriptionId)
            } else {
                send(UnsubscribeTerminalsRequest(cwd: workspace.cwd, workspaceId: workspaceId))
            }
        }
        for terminal in terminals(in: workspaceId) {
            detach(terminal.id)
        }
        terminalsByWorkspace[workspaceId] = nil
        scriptsByWorkspace[workspaceId] = nil
    }

    /// Re-fetches the terminal list. The live subscription also refreshes it on every change.
    public func refreshTerminals(in workspaceId: String) async {
        do {
            let response = try await client.send(
                ListTerminalsRequest(
                    cwd: watched[workspaceId]?.cwd, workspaceId: workspaceId))
            guard !Task.isCancelled else { return }
            terminalsByWorkspace[workspaceId] = response.terminals
            error = nil
        } catch {
            self.error = terminalErrorText(error)
        }
    }

    // MARK: Create and kill

    /// Creates a PTY in `workspaceId`. Returns nil and sets `error` on failure.
    public func createTerminal(
        in workspaceId: String, cwd: String? = nil, name: String? = nil, command: String? = nil,
        args: [String]? = nil, size: TerminalSize? = nil
    ) async -> TerminalInfo? {
        guard let directory = cwd ?? watched[workspaceId]?.cwd else {
            error = "A working directory is required to create a terminal."
            return nil
        }
        do {
            let response = try await client.send(
                CreateTerminalRequest(
                    cwd: directory, workspaceId: workspaceId, name: name, command: command,
                    args: args, size: size))
            if let message = response.error {
                error = message
                return nil
            }
            guard var terminal = response.terminal else {
                error = "The daemon did not return a terminal."
                return nil
            }
            if terminal.workspaceId == nil { terminal.workspaceId = workspaceId }
            if terminal.cwd == nil { terminal.cwd = directory }
            upsert(terminal, in: workspaceId)
            error = nil
            return terminal
        } catch {
            self.error = terminalErrorText(error)
            return nil
        }
    }

    /// Kills a terminal. Returns false and sets `error` when the daemon refuses.
    public func killTerminal(_ terminalId: String) async -> Bool {
        let scriptWorkspaces = workspaceIds(forScriptTerminal: terminalId)
        do {
            let response = try await client.send(KillTerminalRequest(terminalId: terminalId))
            guard response.success else {
                error = "The daemon could not kill this terminal."
                return false
            }
            removeTerminal(terminalId)
            detach(terminalId)
            for workspaceId in scriptWorkspaces {
                await refreshScripts(in: workspaceId)
            }
            error = nil
            return true
        } catch {
            self.error = terminalErrorText(error)
            return false
        }
    }

    // MARK: Attach and detach

    /// Attaches to a terminal at the view's measured grid size.
    ///
    /// The returned stream delivers replay-begin, replay bytes, live output and replay-end (and an
    /// `.exited` when the daemon detaches). Call `detach(_:)` when the view goes away. A reconnect
    /// re-subscribes every active attachment with the same size and replay options.
    public func attach(
        _ terminalId: String, size: TerminalSize,
        restore: TerminalRestoreOptions = .visibleSnapshot
    ) async -> AsyncStream<TerminalOutput> {
        let (stream, continuation) = AsyncStream<TerminalOutput>.makeStream(
            bufferingPolicy: .unbounded)

        guard capabilities.restoreModes else {
            continuation.yield(.exited(error: "Update the host to view terminals."))
            continuation.finish()
            return stream
        }

        detach(terminalId)
        var options = restore
        options.size = size
        let attachment = Attachment(
            id: UUID(), terminalId: terminalId, size: size, restore: options,
            continuation: continuation)
        attachments[terminalId] = attachment

        await establish(attachment, reportTransportFailure: true)
        return stream
    }

    /// Releases this view's subscription. Safe to call twice or before the subscribe response.
    public func detach(_ terminalId: String) {
        guard let attachment = attachments.removeValue(forKey: terminalId) else { return }
        if let slot = attachment.slot {
            slotTerminalIds.removeValue(forKey: slot)
        }
        attachment.continuation.finish()
        releaseStream(terminalId, subscriptionId: attachment.subscriptionId)
    }

    // MARK: Input and resize

    public func sendInput(_ text: String, to terminalId: String) {
        guard !text.isEmpty else { return }
        send(TerminalInput.input(text, terminalId: terminalId))
    }

    /// Bytes are carried as a UTF-8 string on the wire, which is the only input path first-party
    /// clients use. Invalid UTF-8 cannot be represented; those bytes are replaced.
    public func sendInput(_ bytes: Data, to terminalId: String) {
        sendInput(String(decoding: bytes, as: UTF8.self), to: terminalId)
    }

    /// Sends a resize. Use `.claim` on focus and `.update` for later geometry changes from this
    /// view. Hosts without `terminal-size-ownership` treat every resize as a claim.
    public func resize(_ terminalId: String, to size: TerminalSize, intent: TerminalResizeIntent) {
        send(
            TerminalInput.resize(
                rows: size.rows, cols: size.cols, intent: intent, terminalId: terminalId))
    }

    // MARK: Capture

    /// The terminal's text rows, for copy/paste. Nil when the daemon call fails.
    public func capture(
        _ terminalId: String, start: Int? = nil, end: Int? = nil, stripAnsi: Bool = true
    ) async -> [String]? {
        do {
            let response = try await client.send(
                CaptureTerminalRequest(
                    terminalId: terminalId, start: start, end: end, stripAnsi: stripAnsi))
            error = nil
            return response.lines
        } catch {
            self.error = terminalErrorText(error)
            return nil
        }
    }

    // MARK: Scripts

    public func refreshScripts(in workspaceId: String) async {
        guard capabilities.workspaceScriptManagement else {
            scriptsByWorkspace[workspaceId] = []
            return
        }
        loadingScriptWorkspaces.insert(workspaceId)
        defer { loadingScriptWorkspaces.remove(workspaceId) }
        do {
            let response = try await client.send(
                ListWorkspaceScriptsRequest(workspaceId: workspaceId))
            guard !Task.isCancelled else { return }
            if let scripts = response.scripts { scriptsByWorkspace[workspaceId] = scripts }
            if let message = response.error {
                error = message
            } else {
                error = nil
            }
        } catch {
            self.error = terminalErrorText(error)
        }
    }

    /// Starts a configured script. Returns its refreshed row, or nil and sets `error`.
    public func startScript(_ scriptName: String, in workspaceId: String) async -> WorkspaceScript? {
        guard capabilities.workspaceScriptManagement else {
            error = "This host does not support workspace scripts."
            return nil
        }
        do {
            let response = try await client.send(
                StartWorkspaceScriptRequest(workspaceId: workspaceId, scriptName: scriptName))
            if let scripts = response.scripts { scriptsByWorkspace[workspaceId] = scripts }
            if let message = response.error {
                error = message
                return nil
            }
            error = nil
            if let script = response.script {
                upsert(script, in: workspaceId)
                return script
            }
            return scripts(in: workspaceId).first { $0.scriptName == scriptName }
        } catch {
            self.error = terminalErrorText(error)
            return nil
        }
    }

    /// Stops a configured script by stopping its supervised terminal.
    public func stopScript(_ scriptName: String, in workspaceId: String) async -> WorkspaceScript? {
        guard capabilities.workspaceScriptManagement else {
            error = "This host does not support workspace scripts."
            return nil
        }
        do {
            let response = try await client.send(
                StopWorkspaceScriptRequest(workspaceId: workspaceId, scriptName: scriptName))
            if let scripts = response.scripts { scriptsByWorkspace[workspaceId] = scripts }
            if let message = response.error {
                error = message
                return nil
            }
            error = nil
            if let script = response.script {
                upsert(script, in: workspaceId)
                return script
            }
            return scripts(in: workspaceId).first { $0.scriptName == scriptName }
        } catch {
            self.error = terminalErrorText(error)
            return nil
        }
    }

    // MARK: HostSession handoff

    /// Connection changes drive capabilities, reconnect resubscription and stream teardown.
    internal func handle(connection state: ConnectionState) async {
        connectionState = state
        switch state {
        case .connected(let info):
            capabilities = Capabilities(serverInfo: info)
            if sawReconnect {
                sawReconnect = false
                wasConnected = true
                await resync()
            } else {
                wasConnected = true
                for (workspaceId, workspace) in watched {
                    subscribeDirectory(workspaceId: workspaceId, cwd: workspace.cwd)
                }
                // `open` may have run before the first connection was established.
                for workspaceId in watched.keys {
                    await refreshScripts(in: workspaceId)
                }
            }

        case .reconnecting:
            sawReconnect = true
            markDisconnected()

        case .connecting:
            markDisconnected()

        case .idle:
            markDisconnected()
            if wasConnected { finishAllAttachments(error: "Disconnected.") }
            wasConnected = false

        case .failed(let failure):
            markDisconnected()
            finishAllAttachments(error: terminalErrorText(failure))
            wasConnected = false
        }
    }

    /// Terminal stream frames are WebSocket binary frames; only the slot is read here.
    internal func handle(binaryFrame data: Data) {
        guard let frame = TerminalStreamFrame(decoding: data),
            let terminalId = slotTerminalIds[frame.slot],
            attachments[terminalId] != nil
        else { return }

        switch frame.opcode {
        case .output:
            attachments[terminalId]?.continuation.yield(.output(frame.payload))

        case .replayBegin:
            let metadata =
                frame.replayMetadata
                ?? TerminalReplayMetadata(rows: 0, cols: 0, retainedHistoryLines: 0)
            attachments[terminalId]?.isReplaying = true
            attachments[terminalId]?.continuation.yield(.replayBegin(metadata))

        case .replayData:
            attachments[terminalId]?.continuation.yield(.output(frame.payload))

        case .replayEnd:
            attachments[terminalId]?.isReplaying = false
            attachments[terminalId]?.continuation.yield(.replayEnd)

        // Legacy hosts coalesce the whole replay into one 0x05 frame. Normalize it into the same
        // marker sequence so the renderer has one path.
        case .restore:
            attachments[terminalId]?.continuation.yield(
                .replayBegin(TerminalReplayMetadata(rows: 0, cols: 0, retainedHistoryLines: 0)))
            attachments[terminalId]?.continuation.yield(.output(frame.payload))
            attachments[terminalId]?.continuation.yield(.replayEnd)

        case .snapshot:
            // 0x04 is dead on modern hosts and has no rendering runtime here.
            break

        case .input, .resize, .unknown:
            break
        }
    }

    /// JSON pushes this ticket owns. Anything else is ignored.
    internal func handle(messageType: String, raw: Data) {
        let decoder = JSONDecoder()
        switch messageType {
        case "terminals_changed":
            guard let payload = try? decoder.decode(
                SessionPayloadEnvelope<TerminalsChanged>.self, from: raw
            ).payload else { return }
            apply(payload)

        case "terminal_stream_exit":
            guard let payload = try? decoder.decode(
                SessionPayloadEnvelope<TerminalStreamExit>.self, from: raw
            ).payload else { return }
            if let message = payload.error { error = message }
            if attachments[payload.terminalId] != nil {
                finishAttachment(payload.terminalId, error: payload.error)
            }

        case "script_status_update":
            guard let payload = try? decoder.decode(
                SessionPayloadEnvelope<ScriptStatusUpdate>.self, from: raw
            ).payload else { return }
            scriptsByWorkspace[payload.workspaceId] = payload.scripts

        case "terminal_attention_required":
            guard let payload = try? decoder.decode(
                SessionPayloadEnvelope<TerminalAttentionRequired>.self, from: raw
            ).payload else { return }
            applyAttention(payload)

        default:
            return
        }
    }

    // MARK: Internals

    private struct WatchedWorkspace {
        var cwd: String?
    }

    private struct Attachment {
        let id: UUID
        let terminalId: String
        var size: TerminalSize
        var restore: TerminalRestoreOptions
        var slot: UInt8?
        /// Server-assigned stream subscription id, present only on modern sockets.
        var subscriptionId: String?
        var isReplaying = false
        let continuation: AsyncStream<TerminalOutput>.Continuation
    }

    private func establish(_ attachment: Attachment, reportTransportFailure: Bool) async {
        do {
            let response = try await client.send(
                SubscribeTerminalRequest(
                    terminalId: attachment.terminalId, restore: attachment.restore))

            // The view detached while the response was in flight: release the subscription we
            // just got, by id on a modern socket and through the legacy RPC otherwise.
            guard attachments[attachment.terminalId]?.id == attachment.id else {
                if response.slot != nil {
                    await client.releaseSubscription(response.subscriptionId) { [client] in
                        _ = try? await client.send(
                            UnsubscribeTerminalRequest(terminalId: attachment.terminalId))
                    }
                }
                return
            }

            guard response.error == nil, let slot = response.slot else {
                finishAttachment(
                    attachment.terminalId,
                    error: response.error ?? "The daemon did not return a terminal slot.")
                return
            }

            if let previous = attachments[attachment.terminalId]?.slot {
                slotTerminalIds.removeValue(forKey: previous)
            }
            attachments[attachment.terminalId]?.slot = slot
            attachments[attachment.terminalId]?.subscriptionId = response.subscriptionId
            attachments[attachment.terminalId]?.isReplaying = false
            slotTerminalIds[slot] = attachment.terminalId
            error = nil
        } catch {
            guard attachments[attachment.terminalId]?.id == attachment.id else { return }
            if reportTransportFailure {
                finishAttachment(attachment.terminalId, error: terminalErrorText(error))
            } else {
                // A reconnect may still be settling. Keep the view's stream open for the next try.
                self.error = terminalErrorText(error)
            }
        }
    }

    private func resync() async {
        for (workspaceId, workspace) in watched {
            subscribeDirectory(workspaceId: workspaceId, cwd: workspace.cwd)
        }
        for workspaceId in watched.keys {
            await refreshTerminals(in: workspaceId)
            await refreshScripts(in: workspaceId)
        }
        for terminalId in Array(attachments.keys) {
            guard let attachment = attachments[terminalId] else { continue }
            if let slot = attachment.slot {
                slotTerminalIds.removeValue(forKey: slot)
                attachments[terminalId]?.slot = nil
            }
            // The daemon forgot every subscription with the socket; ids are re-learned below.
            attachments[terminalId]?.subscriptionId = nil
            guard let current = attachments[terminalId] else { continue }
            await establish(current, reportTransportFailure: false)
        }
    }

    private func markDisconnected() {
        slotTerminalIds.removeAll()
        directorySubscriptionIds.removeAll()
        for terminalId in attachments.keys {
            attachments[terminalId]?.slot = nil
            attachments[terminalId]?.subscriptionId = nil
            attachments[terminalId]?.isReplaying = false
        }
    }

    private func finishAttachment(_ terminalId: String, error message: String?) {
        guard let attachment = attachments.removeValue(forKey: terminalId) else { return }
        if let slot = attachment.slot {
            slotTerminalIds.removeValue(forKey: slot)
        }
        attachment.continuation.yield(.exited(error: message))
        attachment.continuation.finish()
    }

    private func finishAllAttachments(error message: String) {
        for terminalId in Array(attachments.keys) {
            finishAttachment(terminalId, error: message)
        }
    }

    private func apply(_ payload: TerminalsChanged) {
        let workspaceId = payload.workspaceId ?? workspaceId(matchingCwd: payload.cwd)
        guard let workspaceId else { return }
        if let subscriptionId = payload.subscriptionId {
            directorySubscriptionIds[workspaceId] = subscriptionId
        }
        terminalsByWorkspace[workspaceId] = payload.terminals
    }

    /// Sends the directory subscribe with a fresh `requestId`. A modern daemon refuses an owned
    /// subscription whose request has no `requestId` ("Owned subscriptions require a requestId",
    /// `session/owned-subscriptions/index.ts:286-288`), and the first snapshot echoes it.
    private func subscribeDirectory(workspaceId: String, cwd: String?) {
        send(
            SubscribeTerminalsRequest(
                cwd: cwd, workspaceId: workspaceId, requestId: UUID().uuidString))
    }

    /// Releases a terminal stream: by the server-assigned id on a modern socket, through the
    /// legacy `unsubscribe_terminal_request` otherwise (the daemon strips the id on legacy).
    private func releaseStream(_ terminalId: String, subscriptionId: String?) {
        if let subscriptionId, !subscriptionId.isEmpty {
            releaseOwned(subscriptionId)
        } else {
            send(UnsubscribeTerminalRequest(terminalId: terminalId))
        }
    }

    /// Fire-and-forget modern release. There is no response to wait for.
    private func releaseOwned(_ subscriptionId: String) {
        let client = self.client
        Task { await client.releaseOwnedSubscription(subscriptionId) }
    }

    private func applyAttention(_ payload: TerminalAttentionRequired) {
        let activity = TerminalActivity(
            state: .attention, attentionReason: reason(for: payload.reason),
            changedAt: Date().timeIntervalSince1970 * 1000)
        let candidates = payload.workspaceId.map { [$0] } ?? Array(terminalsByWorkspace.keys)
        for workspaceId in candidates {
            guard var terminals = terminalsByWorkspace[workspaceId],
                let index = terminals.firstIndex(where: { $0.id == payload.terminalId })
            else { continue }
            terminals[index].activity = activity
            terminalsByWorkspace[workspaceId] = terminals
        }
    }

    private func reason(for reason: TerminalAttentionReason) -> TerminalAttentionReason? {
        switch reason {
        case .finished, .needsInput, .unknown: return reason
        }
    }

    private func workspaceId(matchingCwd cwd: String?) -> String? {
        guard let cwd else { return nil }
        return watched.first { $0.value.cwd == cwd }?.key
    }

    private func upsert(_ terminal: TerminalInfo, in workspaceId: String) {
        var terminals = terminalsByWorkspace[workspaceId] ?? []
        terminals.removeAll { $0.id == terminal.id }
        terminals.append(terminal)
        terminalsByWorkspace[workspaceId] = terminals
    }

    private func upsert(_ script: WorkspaceScript, in workspaceId: String) {
        var scripts = scriptsByWorkspace[workspaceId] ?? []
        scripts.removeAll { $0.scriptName == script.scriptName }
        scripts.append(script)
        scriptsByWorkspace[workspaceId] = scripts
    }

    private func removeTerminal(_ terminalId: String) {
        for workspaceId in Array(terminalsByWorkspace.keys) {
            guard var terminals = terminalsByWorkspace[workspaceId],
                terminals.contains(where: { $0.id == terminalId })
            else { continue }
            terminals.removeAll { $0.id == terminalId }
            terminalsByWorkspace[workspaceId] = terminals
        }
    }

    private func workspaceIds(forScriptTerminal terminalId: String) -> [String] {
        scriptsByWorkspace.compactMap { workspaceId, scripts in
            scripts.contains { $0.terminalId == terminalId } ? workspaceId : nil
        }
    }

    /// Fire-and-forget on the wire. There is no response to await, so failures land in `error`.
    private func send<M: PaseoOutboundMessage>(_ message: M) {
        let client = self.client
        Task { [weak self] in
            do {
                try await client.send(message)
            } catch {
                self?.error = terminalErrorText(error)
            }
        }
    }
}

private func terminalErrorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}
