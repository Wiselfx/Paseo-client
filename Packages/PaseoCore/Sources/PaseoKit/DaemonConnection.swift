import Foundation
import PaseoProtocol
import Synchronization

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The real `DaemonClient`: one WebSocket to one daemon, with hello, request/response matching,
/// unsolicited-event routing, keepalive and automatic reconnection.
///
/// IMPLEMENTATION TICKET: docs/tickets/T1-daemon-connection.md
public final class DaemonConnection: DaemonClient, @unchecked Sendable {
    public let endpoint: DaemonEndpoint
    public let clientId: String
    public let appVersion: String?
    public let configuration: Configuration

    /// Timings. Defaults suit a phone; tests pass small values.
    public struct Configuration: Sendable {
        /// How long `connect()` waits for `server_info` after sending hello.
        public var helloTimeout: Duration = .seconds(15)
        /// How often to send `{"type":"ping"}` while connected.
        public var pingInterval: Duration = .seconds(20)
        /// No frame at all for this long means the socket is dead: reconnect.
        public var idleTimeout: Duration = .seconds(45)
        /// Delay before reconnect attempt n is `min(base * 2^(n-1), max)` plus up to 20% jitter.
        public var reconnectBaseDelay: Duration = .milliseconds(500)
        public var reconnectMaxDelay: Duration = .seconds(15)
        public init() {}
    }

    // MARK: Mutable state

    /// Everything that can be touched from more than one task. Guarded by `mutex`; never held
    /// across an `await`.
    private struct Core {
        var state: ConnectionState = .idle
        /// Bumped by every `connect()`/`disconnect()`; async work checks it before mutating.
        var generation = 0
        var transport: (any WebSocketTransport)?
        /// Identifies the receive loop that belongs to the current transport.
        var transportID = 0
        var hello: HelloWaiter?
        var pending: [String: RequestWaiter] = [:]
        var keepaliveTasks: [Task<Void, Never>] = []
        var reconnectTask: Task<Void, Never>?
        var attempt = 0
        var lastFrameAt = ContinuousClock.now
    }

    private let mutex = Mutex(Core())
    private let eventsStream: AsyncStream<DaemonEvent>
    private let eventContinuation: AsyncStream<DaemonEvent>.Continuation
    private let statesStream: AsyncStream<ConnectionState>
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation
    private let transportFactory: WebSocketTransportFactory

    /// - Parameters:
    ///   - clientId: stable per install. The daemon uses it for presence and notifications.
    ///   - transportFactory: injected so tests can run without a network.
    public init(
        endpoint: DaemonEndpoint,
        clientId: String,
        appVersion: String?,
        configuration: Configuration = Configuration(),
        transportFactory: @escaping WebSocketTransportFactory = { URLSessionWebSocketTransport(url: $0) }
    ) {
        self.endpoint = endpoint
        self.clientId = clientId
        self.appVersion = appVersion
        self.configuration = configuration
        self.transportFactory = transportFactory

        let (events, eventContinuation) = AsyncStream.makeStream(
            of: DaemonEvent.self, bufferingPolicy: .unbounded)
        self.eventsStream = events
        self.eventContinuation = eventContinuation

        let (states, stateContinuation) = AsyncStream.makeStream(
            of: ConnectionState.self, bufferingPolicy: .unbounded)
        self.statesStream = states
        self.stateContinuation = stateContinuation

        // Every state change, starting with the current state.
        stateContinuation.yield(.idle)
    }

    /// Opens the socket, sends `Hello`, and returns once `server_info` arrives.
    /// Throws `ConnectionError.rejected` without retrying when the daemon refuses the hello.
    /// After success, a dropped socket reconnects by itself until `disconnect()`.
    @discardableResult
    public func connect() async throws -> ServerInfo {
        if let connected = mutex.withLock({ core -> ServerInfo? in
            if case .connected(let info) = core.state { return info }
            return nil
        }) {
            return connected
        }

        let generation = beginFreshLifecycle()

        do {
            let (info, transportID) = try await performHandshake(generation: generation)
            guard transition(generation: generation, to: .connected(info)) else {
                closeTransport(id: transportID, code: 1000)
                throw ConnectionError.disconnected
            }
            mutex.withLock { core in
                core.attempt = 0
            }
            startKeepalive(generation: generation, transportID: transportID)
            return info
        } catch {
            let connectionError = error as? ConnectionError ?? .transport(String(describing: error))
            failConnect(generation: generation, error: connectionError)
            throw connectionError
        }
    }

    /// Closes for good. In-flight requests fail with `.disconnected`. State becomes `.idle`.
    public func disconnect() {
        let (transport, hello, tasks) = mutex.withLock {
            core -> ((any WebSocketTransport)?, HelloWaiter?, [Task<Void, Never>]) in
            core.generation += 1
            let transport = core.transport
            core.transport = nil
            core.transportID += 1
            let hello = core.hello
            core.hello = nil
            core.attempt = 0
            let tasks = core.keepaliveTasks
            core.keepaliveTasks = []
            core.reconnectTask?.cancel()
            core.reconnectTask = nil
            return (transport, hello, tasks)
        }

        tasks.forEach { $0.cancel() }
        hello?.resolve(.failure(.disconnected))
        failAllPending(with: .disconnected)
        transport?.close(code: 1000)
        setState(.idle)
    }

    public func initiate<R: PaseoRequest>(_ request: R, timeout: Duration) async throws -> InitiatedResponse<R> {
        let isConnected = mutex.withLock { core -> Bool in
            if case .connected = core.state, core.transport != nil { return true }
            return false
        }
        guard isConnected else { throw ConnectionError.disconnected }

        // Honor a pre-set requestId: callers that stream correlated binary frames (file upload)
        // choose their id up front. Everyone else leaves it empty and gets a fresh UUID.
        let requestId = request.requestId.isEmpty ? UUID().uuidString : request.requestId
        var request = request
        request.requestId = requestId

        let frame: Data
        do {
            frame = try JSONEncoder().encode(SessionRequestEnvelope(request))
        } catch {
            throw ConnectionError.protocolViolation("could not encode \(R.type): \(error)")
        }
        guard let text = String(data: frame, encoding: .utf8) else {
            throw ConnectionError.protocolViolation("\(R.type) did not encode as UTF-8")
        }

        // Register before sending so a very fast response cannot be missed.
        let waiter = RequestWaiter()
        let transport = mutex.withLock { core -> (any WebSocketTransport)? in
            guard case .connected = core.state, let transport = core.transport else { return nil }
            core.pending[requestId] = waiter
            return transport
        }
        guard let transport else {
            _ = mutex.withLock { core in core.pending.removeValue(forKey: requestId) }
            throw ConnectionError.disconnected
        }

        // Write the frame before returning. A caller that streams binary frames afterwards
        // (file upload) then has them ride the same socket in a deterministic order.
        do {
            try await transport.send(text: text)
        } catch {
            let mapped = Self.connectionError(from: error)
            resolvePending(requestId, with: .failure(mapped))
            throw mapped
        }

        startTimeout(requestId: requestId, timeout: timeout)
        return InitiatedResponse(requestId: requestId) {
            let data = try await waiter.wait()
            do {
                return try JSONDecoder().decode(SessionPayloadEnvelope<R.Response>.self, from: data).payload
            } catch {
                throw ConnectionError.protocolViolation("could not decode \(R.responseType): \(error)")
            }
        }
    }

    public func send<R: PaseoRequest>(_ request: R, timeout: Duration) async throws -> R.Response {
        try await initiate(request, timeout: timeout).value()
    }

    private func startTimeout(requestId: String, timeout: Duration) {
        Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            self?.resolvePending(requestId, with: .failure(.timeout))
        }
    }

    public var events: AsyncStream<DaemonEvent> { eventsStream }
    public var states: AsyncStream<ConnectionState> { statesStream }

    public func send<M: PaseoOutboundMessage>(_ message: M) async throws {
        let transport = mutex.withLock { core -> (any WebSocketTransport)? in
            guard case .connected = core.state, let transport = core.transport else { return nil }
            return transport
        }
        guard let transport else { throw ConnectionError.disconnected }

        let data: Data
        do {
            data = try JSONEncoder().encode(SessionOutboundEnvelope(message))
        } catch {
            throw ConnectionError.protocolViolation("could not encode \(M.type): \(error)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConnectionError.protocolViolation("\(M.type) did not encode as UTF-8")
        }
        do {
            try await transport.send(text: text)
        } catch {
            throw Self.connectionError(from: error)
        }
    }

    public func send(binary: Data) async throws {
        let transport = mutex.withLock { core -> (any WebSocketTransport)? in
            guard case .connected = core.state, let transport = core.transport else { return nil }
            return transport
        }
        guard let transport else { throw ConnectionError.disconnected }

        do {
            try await transport.send(binary: binary)
        } catch {
            throw Self.connectionError(from: error)
        }
    }

    // MARK: Lifecycle helpers

    /// Invalidates old async work, fails old requests, closes the old socket and moves to
    /// `.connecting`. Returns the new generation to stamp on this lifecycle.
    private func beginFreshLifecycle() -> Int {
        let (generation, transport, hello, tasks) = mutex.withLock {
            core -> (Int, (any WebSocketTransport)?, HelloWaiter?, [Task<Void, Never>]) in
            core.generation += 1
            core.attempt = 0
            let transport = core.transport
            core.transport = nil
            core.transportID += 1
            let hello = core.hello
            core.hello = nil
            let tasks = core.keepaliveTasks
            core.keepaliveTasks = []
            core.reconnectTask?.cancel()
            core.reconnectTask = nil
            return (core.generation, transport, hello, tasks)
        }

        tasks.forEach { $0.cancel() }
        hello?.resolve(.failure(.disconnected))
        failAllPending(with: .disconnected)
        transport?.close(code: 1000)
        transition(generation: generation, to: .connecting)
        return generation
    }

    /// Creates a transport, starts its receive loop, sends hello and waits for `server_info`.
    /// On success the transport is installed and the receive loop keeps running.
    private func performHandshake(generation: Int) async throws -> (ServerInfo, Int) {
        let transport = transportFactory(endpoint.url)
        let hello = HelloWaiter()

        let transportID = mutex.withLock { core -> Int in
            guard core.generation == generation else { return 0 }
            core.transportID += 1
            let id = core.transportID
            core.transport = transport
            core.hello = hello
            core.lastFrameAt = ContinuousClock.now
            return id
        }
        guard transportID != 0 else {
            transport.close(code: 1000)
            throw ConnectionError.disconnected
        }

        Task { [weak self] in
            await self?.receiveLoop(transport: transport, transportID: transportID, generation: generation)
        }

        let helloText: String
        do {
            let data = try JSONEncoder().encode(
                Hello(clientId: clientId, appVersion: appVersion, credential: endpoint.credential))
            guard let text = String(data: data, encoding: .utf8) else {
                throw ConnectionError.protocolViolation("hello did not encode as UTF-8")
            }
            helloText = text
        } catch {
            abortHandshake(generation: generation, transportID: transportID)
            throw error as? ConnectionError ?? .protocolViolation(String(describing: error))
        }

        do {
            try await transport.send(text: helloText)
        } catch {
            let mapped = Self.connectionError(from: error)
            abortHandshake(generation: generation, transportID: transportID)
            hello.resolve(.failure(mapped))
            throw mapped
        }

        do {
            let info = try await hello.wait(timeout: configuration.helloTimeout)
            let stillCurrent = mutex.withLock { core -> Bool in
                guard core.generation == generation, core.transportID == transportID,
                    core.transport != nil
                else { return false }
                if core.hello === hello { core.hello = nil }
                return true
            }
            guard stillCurrent else {
                transport.close(code: 1000)
                throw ConnectionError.disconnected
            }
            return (info, transportID)
        } catch {
            let mapped = error as? ConnectionError ?? .transport(String(describing: error))
            abortHandshake(generation: generation, transportID: transportID)
            throw mapped
        }
    }

    /// Drops the transport of a failed handshake. Never triggers a reconnect: only a socket that
    /// was already `.connected` reconnects.
    private func abortHandshake(generation: Int, transportID: Int) {
        let transport = mutex.withLock { core -> (any WebSocketTransport)? in
            guard core.generation == generation, core.transportID == transportID else { return nil }
            core.hello = nil
            let transport = core.transport
            core.transport = nil
            core.transportID += 1
            return transport
        }
        transport?.close(code: 1000)
    }

    /// A failed `connect()`. A `disconnect()` that raced us wins: it already moved to `.idle`.
    private func failConnect(generation: Int, error: ConnectionError) {
        let transport = mutex.withLock { core -> (any WebSocketTransport)? in
            guard core.generation == generation else { return nil }
            core.hello = nil
            let transport = core.transport
            core.transport = nil
            core.transportID += 1
            return transport
        }
        transport?.close(code: 1000)
        mutex.withLock { core in
            if core.keepaliveTasks.isEmpty == false {
                core.keepaliveTasks.forEach { $0.cancel() }
                core.keepaliveTasks = []
            }
        }
        transition(generation: generation, to: .failed(error), skipIfIdle: true)
    }

    private func failAllPending(with error: ConnectionError) {
        let waiters = mutex.withLock { core -> [RequestWaiter] in
            let waiters = Array(core.pending.values)
            core.pending.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }

    @discardableResult
    private func resolvePending(_ requestId: String, with result: Result<Data, ConnectionError>) -> Bool {
        let waiter = mutex.withLock { core -> RequestWaiter? in
            core.pending.removeValue(forKey: requestId)
        }
        guard let waiter else { return false }
        waiter.resume(with: result)
        return true
    }

    // MARK: State

    @discardableResult
    private func transition(
        generation: Int, to newState: ConnectionState, skipIfIdle: Bool = false
    ) -> Bool {
        let changed = mutex.withLock { core -> Bool in
            guard core.generation == generation else { return false }
            if skipIfIdle, case .idle = core.state { return false }
            guard core.state != newState else { return false }
            core.state = newState
            return true
        }
        if changed {
            stateContinuation.yield(newState)
        }
        return changed
    }

    private func setState(_ newState: ConnectionState) {
        let changed = mutex.withLock { core -> Bool in
            guard core.state != newState else { return false }
            core.state = newState
            return true
        }
        if changed {
            stateContinuation.yield(newState)
        }
    }

    // MARK: Receive loop

    private func receiveLoop(
        transport: any WebSocketTransport, transportID: Int, generation: Int
    ) async {
        while !Task.isCancelled {
            let frame: WebSocketFrame
            do {
                frame = try await transport.receive()
            } catch {
                socketFailed(
                    transport: transport, transportID: transportID, generation: generation,
                    error: Self.connectionError(from: error))
                return
            }

            let isCurrent = mutex.withLock { core -> Bool in
                guard core.generation == generation, core.transportID == transportID,
                    core.transport != nil
                else { return false }
                // Any frame counts as life, even one we cannot decode.
                core.lastFrameAt = ContinuousClock.now
                return true
            }
            guard isCurrent else { return }
            handleFrame(frame, transportID: transportID, generation: generation)
        }
    }

    private func handleFrame(_ frame: WebSocketFrame, transportID: Int, generation: Int) {
        let data: Data
        switch frame {
        case .binary(let binary):
            emitEvent(.binaryFrame(binary))
            return
        case .text(let text):
            guard let encoded = text.data(using: .utf8) else { return }
            data = encoded
        }

        guard let header = try? JSONDecoder().decode(InboundHeader.self, from: data) else { return }

        switch header.type {
        case "pong":
            return
        case "hello.rejected":
            let reason = (try? JSONDecoder().decode(HelloRejected.self, from: data).reason) ?? "rejected"
            rejectHello(transportID: transportID, generation: generation, reason: reason)
        case "session":
            routeSession(header: header, data: data, transportID: transportID, generation: generation)
        default:
            return
        }
    }

    private func routeSession(
        header: InboundHeader, data: Data, transportID: Int, generation: Int
    ) {
        if header.status == "server_info" {
            let waiter = mutex.withLock { core -> HelloWaiter? in
                guard core.generation == generation, core.transportID == transportID else { return nil }
                let waiter = core.hello
                core.hello = nil
                return waiter
            }
            guard let waiter else { return }
            if let info = try? JSONDecoder().decode(SessionPayloadEnvelope<ServerInfo>.self, from: data)
                .payload
            {
                waiter.resolve(.success(info))
            } else {
                waiter.resolve(
                    .failure(.protocolViolation("server_info payload did not decode")))
            }
            return
        }

        // Some events carry a requestId-shaped field in their payload (the daemon's
        // `subscription:<cwd>` status id). Only a message whose type is a response may settle a
        // pending request; everything else is an event.
        if let requestId = header.requestId, Self.isResponseType(header.messageType),
            resolvePending(requestId, with: .success(data))
        {
            return
        }

        guard let messageType = header.messageType else { return }

        switch messageType {
        case "agent_stream":
            if let payload = try? JSONDecoder().decode(
                SessionPayloadEnvelope<AgentStreamPayload>.self, from: data
            ).payload {
                emitEvent(.agentStream(payload))
            } else {
                emitEvent(.unhandled(messageType: messageType, raw: data))
            }
        case "agent_update":
            if let payload = try? JSONDecoder().decode(SessionPayloadEnvelope<AgentUpdate>.self, from: data)
                .payload
            {
                emitEvent(.agentUpdate(payload))
            } else {
                emitEvent(.unhandled(messageType: messageType, raw: data))
            }
        case "agent.timeline.replacement":
            if let payload = try? JSONDecoder().decode(
                SessionPayloadEnvelope<TimelineReplacement>.self, from: data
            ).payload {
                emitEvent(.timelineReplacement(agentId: payload.agentId, epoch: payload.epoch))
            } else {
                emitEvent(.unhandled(messageType: messageType, raw: data))
            }
        default:
            // A response for a request we already gave up on: drop it silently.
            if header.requestId != nil, Self.isResponseType(messageType) { return }
            emitEvent(.unhandled(messageType: messageType, raw: data))
        }
    }

    /// Response types that correlate a pending request without the usual `_response` suffix.
    /// `create_agent_request` answers with `status`, permission answers with
    /// `agent_permission_resolved`, and archive answers with the `agent_archived` broadcast.
    private static let correlatedResponseTypes: Set<String> = [
        "status", "agent_archived", "agent_deleted", "agent_permission_resolved",
    ]

    /// A message type that may settle a pending request or is a late response we should drop.
    /// Schedules use slash-namespaced types such as `schedule/list/response`.
    private static func isResponseType(_ messageType: String?) -> Bool {
        guard let messageType else { return false }
        return messageType.hasSuffix("_response") || messageType.hasSuffix(".response")
            || messageType.hasSuffix("/response") || correlatedResponseTypes.contains(messageType)
    }

    private struct TimelineReplacement: Decodable, Sendable {
        var agentId: String
        var epoch: String
    }

    private func rejectHello(transportID: Int, generation: Int, reason: String) {
        let waiter = mutex.withLock { core -> HelloWaiter? in
            guard core.generation == generation, core.transportID == transportID else { return nil }
            let waiter = core.hello
            core.hello = nil
            return waiter
        }
        waiter?.resolve(.failure(.rejected(reason: reason)))
    }

    private func emitEvent(_ event: DaemonEvent) {
        eventContinuation.yield(event)
    }

    // MARK: Socket failure and reconnect

    private func socketFailed(
        transport: any WebSocketTransport, transportID: Int, generation: Int, error: ConnectionError
    ) {
        enum Action {
            case none
            case failHello(HelloWaiter, ConnectionError)
            case reconnect(ConnectionError)
            case reject(ConnectionError)
        }

        let action = mutex.withLock { core -> Action in
            guard core.generation == generation, core.transportID == transportID else { return .none }

            if let waiter = core.hello {
                core.hello = nil
                core.transport = nil
                core.transportID += 1
                return .failHello(waiter, Self.rejectionOr(error))
            }

            guard core.transport != nil else { return .none }

            if case .connected = core.state {
                core.transport = nil
                core.transportID += 1
                // Auth rejection is terminal whether it happens during hello or later.
                if case .closed(let code, _) = error, code == 4401 {
                    return .reject(Self.rejectionOr(error))
                }
                return .reconnect(error)
            }

            return .none
        }

        switch action {
        case .none:
            break
        case .failHello(let waiter, let error):
            waiter.resolve(.failure(error))
            transport.close(code: 1000)
        case .reject(let error):
            cancelKeepalive()
            transport.close(code: 1000)
            failAllPending(with: .disconnected)
            transition(generation: generation, to: .failed(error))
        case .reconnect(let error):
            cancelKeepalive()
            transport.close(code: 1000)
            failAllPending(with: .disconnected)
            startReconnect(generation: generation, lastError: error)
        }
    }

    private func startReconnect(generation: Int, lastError: ConnectionError) {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runReconnect(generation: generation, initialError: lastError)
        }
        let accepted = mutex.withLock { core -> Bool in
            guard core.generation == generation else { return false }
            core.reconnectTask = task
            return true
        }
        if !accepted { task.cancel() }
    }

    private func runReconnect(generation: Int, initialError: ConnectionError) async {
        var lastError = initialError
        var attempt = 0

        while !Task.isCancelled {
            let alive = mutex.withLock { core in core.generation == generation }
            guard alive else { return }

            attempt += 1
            let delay = reconnectDelay(attempt: attempt)
            guard transition(generation: generation, to: .reconnecting(attempt: attempt, lastError: lastError))
            else { return }

            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            let stillAlive = mutex.withLock { core in core.generation == generation }
            guard stillAlive else { return }

            do {
                let (info, transportID) = try await performHandshake(generation: generation)
                guard transition(generation: generation, to: .connected(info)) else {
                    closeTransport(id: transportID, code: 1000)
                    return
                }
                mutex.withLock { core in
                    core.attempt = 0
                    core.reconnectTask = nil
                }
                startKeepalive(generation: generation, transportID: transportID)
                return
            } catch {
                let connectionError = error as? ConnectionError ?? .transport(String(describing: error))
                if case .rejected = connectionError {
                    mutex.withLock { core in core.reconnectTask = nil }
                    transition(generation: generation, to: .failed(connectionError))
                    return
                }
                if case .disconnected = connectionError {
                    let alive = mutex.withLock { core in core.generation == generation }
                    guard alive else { return }
                }
                lastError = connectionError
            }
        }
    }

    private func reconnectDelay(attempt: Int) -> Duration {
        let base = Self.seconds(configuration.reconnectBaseDelay)
        let maximum = Self.seconds(configuration.reconnectMaxDelay)
        let exponent = min(Double(max(attempt - 1, 0)), 62)
        let raw = min(base * pow(2, exponent), maximum)
        let jitter = Double.random(in: 0...0.2)
        return .seconds(raw * (1 + jitter))
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    private func closeTransport(id: Int, code: Int) {
        let transport = mutex.withLock { core -> (any WebSocketTransport)? in
            guard core.transportID == id else { return nil }
            let transport = core.transport
            core.transport = nil
            core.transportID += 1
            core.hello = nil
            return transport
        }
        transport?.close(code: code)
    }

    // MARK: Keepalive

    private func startKeepalive(generation: Int, transportID: Int) {
        let pingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self.configuration.pingInterval)
                } catch {
                    return
                }
                guard let transport = self.liveTransport(generation: generation, transportID: transportID)
                else { return }
                do {
                    try await transport.send(text: #"{"type":"ping"}"#)
                } catch {
                    self.socketFailed(
                        transport: transport, transportID: transportID, generation: generation,
                        error: Self.connectionError(from: error))
                    return
                }
            }
        }

        let idleTask = Task { [weak self] in
            guard let self else { return }
            let idleTimeout = self.configuration.idleTimeout
            while !Task.isCancelled {
                // Sleep only until the current frame would be idleTimeout old, so a busy socket
                // is checked right on time rather than at the next multiple of the timeout.
                let sleepFor = self.mutex.withLock { core -> Duration? in
                    guard core.generation == generation, core.transportID == transportID,
                        core.transport != nil
                    else { return nil }
                    let idleFor = ContinuousClock.now - core.lastFrameAt
                    guard idleFor < idleTimeout else { return .milliseconds(1) }
                    return idleTimeout - idleFor
                }
                guard let sleepFor else { return }
                do {
                    try await Task.sleep(for: sleepFor)
                } catch {
                    return
                }
                let result = self.mutex.withLock {
                    core -> (dead: Bool, transport: any WebSocketTransport)? in
                    guard core.generation == generation, core.transportID == transportID,
                        let transport = core.transport
                    else { return nil }
                    let idleFor = ContinuousClock.now - core.lastFrameAt
                    return (idleFor >= idleTimeout, transport)
                }
                guard let result else { return }
                if result.dead {
                    self.socketFailed(
                        transport: result.transport, transportID: transportID, generation: generation,
                        error: .timeout)
                    return
                }
            }
        }

        let accepted = mutex.withLock { core -> Bool in
            guard core.generation == generation, core.transportID == transportID,
                case .connected = core.state
            else { return false }
            core.keepaliveTasks = [pingTask, idleTask]
            return true
        }
        if !accepted {
            pingTask.cancel()
            idleTask.cancel()
        }
    }

    private func cancelKeepalive() {
        let tasks = mutex.withLock { core -> [Task<Void, Never>] in
            let tasks = core.keepaliveTasks
            core.keepaliveTasks = []
            return tasks
        }
        tasks.forEach { $0.cancel() }
    }

    private func liveTransport(generation: Int, transportID: Int) -> (any WebSocketTransport)? {
        mutex.withLock { core in
            guard core.generation == generation, core.transportID == transportID else { return nil }
            return core.transport
        }
    }

    // MARK: Error mapping

    private static func connectionError(from error: any Error) -> ConnectionError {
        if let connectionError = error as? ConnectionError { return connectionError }
        if let closed = error as? WebSocketClosed { return .closed(code: closed.code, reason: closed.reason) }
        return .transport(String(describing: error))
    }

    /// A 4401 close without a `hello.rejected` frame is still a rejection; the daemon's close
    /// reason is used when present.
    private static func rejectionOr(_ error: ConnectionError) -> ConnectionError {
        if case .closed(let code, let reason) = error, code == 4401 {
            return .rejected(reason: reason.isEmpty ? "password_required" : reason)
        }
        return error
    }
}

/// One-shot handshake waiter. Resolution is idempotent; the timeout is an ordinary race rather
/// than a task-group because the frame router owns the other side of the race.
private final class HelloWaiter: @unchecked Sendable {
    private struct Box {
        var continuation: CheckedContinuation<ServerInfo, any Error>?
        var result: Result<ServerInfo, ConnectionError>?
        var done = false
        var timeoutTask: Task<Void, Never>?
    }

    private let mutex = Mutex(Box())

    func wait(timeout: Duration) async throws -> ServerInfo {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ServerInfo, any Error>) in
            let immediate = mutex.withLock { box -> Result<ServerInfo, ConnectionError>? in
                if box.done { return box.result }
                box.continuation = continuation
                return nil
            }
            if let immediate {
                continuation.resume(with: immediate)
                return
            }
            let task = Task { [weak self] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                self?.resolve(.failure(ConnectionError.timeout))
            }
            let store = mutex.withLock { box -> Bool in
                if box.done { return false }
                box.timeoutTask = task
                return true
            }
            if !store { task.cancel() }
        }
    }

    func resolve(_ result: Result<ServerInfo, ConnectionError>) {
        let (continuation, timeoutTask) = mutex.withLock {
            box -> (CheckedContinuation<ServerInfo, any Error>?, Task<Void, Never>?) in
            guard !box.done else { return (nil, nil) }
            box.done = true
            box.result = result
            let continuation = box.continuation
            box.continuation = nil
            let task = box.timeoutTask
            box.timeoutTask = nil
            return (continuation, task)
        }
        timeoutTask?.cancel()
        continuation?.resume(with: result)
    }
}

/// One pending request. A late response finds no entry and is dropped.
private final class RequestWaiter: @unchecked Sendable {
    private struct Box {
        /// Buffered result, for when the response (or timeout) beats the wait() call.
        var result: Result<Data, ConnectionError>?
        /// Suspended waiter, created lazily inside wait().
        var continuation: CheckedContinuation<Data, any Error>?
    }

    private let mutex = Mutex(Box())

    /// Awaits the daemon's response payload, suspending until `resolvePending` fires.
    /// Replays immediately if the result arrived first.
    func wait() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let immediate = mutex.withLock { box -> Result<Data, ConnectionError>? in
                if let result = box.result { return result }
                box.continuation = continuation
                return nil
            }
            if let immediate { continuation.resume(with: immediate.mapError { $0 as any Error }) }
        }
    }

    func resume(with result: Result<Data, ConnectionError>) {
        let continuation = mutex.withLock { box -> CheckedContinuation<Data, any Error>? in
            if let continuation = box.continuation {
                box.continuation = nil
                return continuation
            }
            box.result = result
            return nil
        }
        continuation?.resume(with: result)
    }

    func resume(throwing error: ConnectionError) {
        resume(with: .failure(error))
    }
}

/// `URLSessionWebSocketTask` behind `WebSocketTransport`. Works on Apple platforms and Linux.
///
/// IMPLEMENTATION TICKET: docs/tickets/T1-daemon-connection.md
public final class URLSessionWebSocketTransport: WebSocketTransport, @unchecked Sendable {
    /// Timeline pages can be several MiB; the 1 MiB default is too small.
    private static let maximumMessageSize = 64 * 1024 * 1024

    private let session: URLSession
    private let task: URLSessionWebSocketTask

    public init(url: URL) {
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration)
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = Self.maximumMessageSize
        self.session = session
        self.task = task
        task.resume()
    }

    public func send(text: String) async throws {
        try await task.send(.string(text))
    }

    public func send(binary: Data) async throws {
        try await task.send(.data(binary))
    }

    public func receive() async throws -> WebSocketFrame {
        #if canImport(FoundationNetworking)
            // swift-corelibs-foundation delivers each libcurl receive buffer as its own
            // `URLSessionWebSocketTask.Message`, even when it is only part of one WebSocket
            // message. Every daemon frame is a single JSON object, so accumulate chunks until
            // the braces balance and hand the whole frame to the connection.
            var accumulator = JSONMessageAccumulator()
            while true {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        if let complete = accumulator.append(text) {
                            return .text(complete)
                        }
                    case .data(let data):
                        accumulator.reset()
                        return .binary(data)
                    @unknown default:
                        throw WebSocketClosed(code: 1002, reason: "unsupported websocket message")
                    }
                } catch {
                    throw mappedReceiveError(error)
                }
            }
        #else
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    return .text(text)
                case .data(let data):
                    return .binary(data)
                @unknown default:
                    throw WebSocketClosed(code: 1002, reason: "unsupported websocket message")
                }
            } catch {
                throw mappedReceiveError(error)
            }
        #endif
    }

    private func mappedReceiveError(_ error: any Error) -> any Error {
        let closeCode = task.closeCode
        guard closeCode != .invalid else { return error }
        // `closeReason` is `Data?` on every platform.
        let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return WebSocketClosed(code: closeCode.rawValue, reason: reason)
    }

    public func close(code: Int) {
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure
        task.cancel(with: closeCode, reason: nil)
        session.invalidateAndCancel()
    }
}

/// Finds the end of one JSON object across arbitrary text chunks. Used only on Linux, where
/// `URLSessionWebSocketTask` splits large messages at buffer boundaries.
private struct JSONMessageAccumulator {
    private var text = ""
    private var depth = 0
    private var started = false
    private var inString = false
    private var escaped = false

    mutating func append(_ chunk: String) -> String? {
        text += chunk
        for character in chunk {
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch character {
            case "\"":
                inString = true
            case "{", "[":
                depth += 1
                started = true
            case "}", "]":
                depth -= 1
            default:
                break
            }
            if started, depth == 0 {
                let complete = text
                reset()
                return complete
            }
        }
        return nil
    }

    mutating func reset() {
        text = ""
        depth = 0
        started = false
        inString = false
        escaped = false
    }
}
