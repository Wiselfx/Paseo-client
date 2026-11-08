import Foundation
import PaseoKit
import PaseoProtocol

/// Test double for `DaemonClient`. Records every request, answers from per-type handlers and lets
/// a test push daemon events and connection states in order.
final class FakeDaemonClient: DaemonClient, @unchecked Sendable {
    enum FakeError: Error, Sendable, Equatable {
        case noHandler(String)
        case unexpectedResponse(String)
    }

    typealias FetchAgentsHandler =
        @Sendable (FetchAgentsRequest) async throws -> FetchAgentsRequest.Response
    typealias FetchTimelineHandler =
        @Sendable (FetchAgentTimelineRequest) async throws -> FetchAgentTimelineRequest.Response
    typealias SendMessageHandler =
        @Sendable (SendAgentMessageRequest) async throws -> SendAgentMessageRequest.Response
    typealias CancelHandler =
        @Sendable (CancelAgentRequest) async throws -> CancelAgentRequest.Response
    typealias SubscriptionHandler =
        @Sendable (SetAgentTimelineSubscriptionRequest) async throws -> SetAgentTimelineSubscriptionRequest.Response
    typealias ListTerminalsHandler =
        @Sendable (ListTerminalsRequest) async throws -> ListTerminalsRequest.Response
    typealias CreateTerminalHandler =
        @Sendable (CreateTerminalRequest) async throws -> CreateTerminalRequest.Response
    typealias SubscribeTerminalHandler =
        @Sendable (SubscribeTerminalRequest) async throws -> SubscribeTerminalRequest.Response
    typealias KillTerminalHandler =
        @Sendable (KillTerminalRequest) async throws -> KillTerminalRequest.Response
    typealias CaptureTerminalHandler =
        @Sendable (CaptureTerminalRequest) async throws -> CaptureTerminalRequest.Response
    typealias ListScriptsHandler =
        @Sendable (ListWorkspaceScriptsRequest) async throws -> ListWorkspaceScriptsRequest.Response
    typealias StartScriptHandler =
        @Sendable (StartWorkspaceScriptRequest) async throws -> StartWorkspaceScriptRequest.Response
    typealias StopScriptHandler =
        @Sendable (StopWorkspaceScriptRequest) async throws -> StopWorkspaceScriptRequest.Response

    let events: AsyncStream<DaemonEvent>
    let states: AsyncStream<ConnectionState>
    private let eventContinuation: AsyncStream<DaemonEvent>.Continuation
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    private let lock = NSLock()
    private var recorded: [any PaseoRequest] = []
    private var recordedMessages: [any PaseoOutboundMessage] = []
    private var fetchAgentsHandler: FetchAgentsHandler?
    private var fetchTimelineHandler: FetchTimelineHandler?
    private var sendMessageHandler: SendMessageHandler?
    private var cancelHandler: CancelHandler?
    private var subscriptionHandler: SubscriptionHandler?
    private var listTerminalsHandler: ListTerminalsHandler?
    private var createTerminalHandler: CreateTerminalHandler?
    private var subscribeTerminalHandler: SubscribeTerminalHandler?
    private var killTerminalHandler: KillTerminalHandler?
    private var captureTerminalHandler: CaptureTerminalHandler?
    private var listScriptsHandler: ListScriptsHandler?
    private var startScriptHandler: StartScriptHandler?
    private var stopScriptHandler: StopScriptHandler?
    /// Every outbound fire-and-forget message, in order (`terminal_input`, subscribes, …).
    var messages: [any PaseoOutboundMessage] { locked { recordedMessages } }
    /// Type-keyed handlers for request types that don't deserve a named property. Checked before
    /// the switch, so a test can add a new wire type without touching this file's existing API.
    private var genericHandlers: [String: @Sendable (any PaseoRequest) async throws -> Any] = [:]

    init() {
        let (events, eventContinuation) = AsyncStream<DaemonEvent>.makeStream(bufferingPolicy: .unbounded)
        let (states, stateContinuation) = AsyncStream<ConnectionState>.makeStream(bufferingPolicy: .unbounded)
        self.events = events
        self.states = states
        self.eventContinuation = eventContinuation
        self.stateContinuation = stateContinuation
    }

    // MARK: Handlers

    func onFetchAgents(_ handler: @escaping FetchAgentsHandler) {
        locked { fetchAgentsHandler = handler }
    }

    func onFetchTimeline(_ handler: @escaping FetchTimelineHandler) {
        locked { fetchTimelineHandler = handler }
    }

    func onSendMessage(_ handler: @escaping SendMessageHandler) {
        locked { sendMessageHandler = handler }
    }

    func onCancel(_ handler: @escaping CancelHandler) {
        locked { cancelHandler = handler }
    }

    func onSetSubscription(_ handler: @escaping SubscriptionHandler) {
        locked { subscriptionHandler = handler }
    }

    func onListTerminals(_ handler: @escaping ListTerminalsHandler) {
        locked { listTerminalsHandler = handler }
    }

    func onCreateTerminal(_ handler: @escaping CreateTerminalHandler) {
        locked { createTerminalHandler = handler }
    }

    func onSubscribeTerminal(_ handler: @escaping SubscribeTerminalHandler) {
        locked { subscribeTerminalHandler = handler }
    }

    func onKillTerminal(_ handler: @escaping KillTerminalHandler) {
        locked { killTerminalHandler = handler }
    }

    func onCaptureTerminal(_ handler: @escaping CaptureTerminalHandler) {
        locked { captureTerminalHandler = handler }
    }

    func onListScripts(_ handler: @escaping ListScriptsHandler) {
        locked { listScriptsHandler = handler }
    }

    func onStartScript(_ handler: @escaping StartScriptHandler) {
        locked { startScriptHandler = handler }
    }

    func onStopScript(_ handler: @escaping StopScriptHandler) {
        locked { stopScriptHandler = handler }
    }

    /// Answers any `PaseoRequest` type by its wire name. Checked before the named handlers, so a
    /// new wire type needs no change to this file's existing API.
    func onSend<R: PaseoRequest>(
        _ type: R.Type = R.self, _ handler: @escaping @Sendable (R) async throws -> R.Response
    ) {
        locked {
            genericHandlers[R.type] = { request in
                guard let typed = request as? R else {
                    throw FakeError.unexpectedResponse(R.type)
                }
                return try await handler(typed)
            }
        }
    }

    // MARK: Pushing traffic

    func push(_ event: DaemonEvent) {
        eventContinuation.yield(event)
    }

    func push(_ state: ConnectionState) {
        stateContinuation.yield(state)
    }

    func finish() {
        eventContinuation.finish()
        stateContinuation.finish()
    }

    // MARK: Recorded requests

    var requests: [any PaseoRequest] { locked { recorded } }

    func requests<R: PaseoRequest>(_ type: R.Type) -> [R] {
        requests.compactMap { $0 as? R }
    }

    // MARK: DaemonClient

    func send<R: PaseoRequest>(_ request: R, timeout: Duration) async throws -> R.Response {
        locked { recorded.append(request) }

        if let handler = locked({ genericHandlers[R.type] }) {
            let value = try await handler(request)
            guard let typed = value as? R.Response else {
                throw FakeError.unexpectedResponse(R.type)
            }
            return typed
        }

        switch request {
        case let request as FetchAgentsRequest:
            guard let handler = locked({ fetchAgentsHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        case let request as FetchAgentTimelineRequest:
            guard let handler = locked({ fetchTimelineHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        case let request as SendAgentMessageRequest:
            guard let handler = locked({ sendMessageHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        case let request as CancelAgentRequest:
            guard let handler = locked({ cancelHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        case let request as SetAgentTimelineSubscriptionRequest:
            guard let handler = locked({ subscriptionHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        case let request as ListTerminalsRequest:
            guard let handler = locked({ listTerminalsHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        case let request as CreateTerminalRequest:
            guard let handler = locked({ createTerminalHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        case let request as SubscribeTerminalRequest:
            guard let handler = locked({ subscribeTerminalHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        case let request as KillTerminalRequest:
            guard let handler = locked({ killTerminalHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        case let request as CaptureTerminalRequest:
            guard let handler = locked({ captureTerminalHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        case let request as ListWorkspaceScriptsRequest:
            guard let handler = locked({ listScriptsHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        case let request as StartWorkspaceScriptRequest:
            guard let handler = locked({ startScriptHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        case let request as StopWorkspaceScriptRequest:
            guard let handler = locked({ stopScriptHandler }) else { throw FakeError.noHandler(R.type) }
            let response = try await handler(request)
            guard let typed = response as? R.Response else { throw FakeError.unexpectedResponse(R.type) }
            return typed

        default:
            throw FakeError.noHandler(R.type)
        }
    }

    func send<M: PaseoOutboundMessage>(_ message: M) async throws {
        locked { recordedMessages.append(message) }
    }

    // MARK: Helpers

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
