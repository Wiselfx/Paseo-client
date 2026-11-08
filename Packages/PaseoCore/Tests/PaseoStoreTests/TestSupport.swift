import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

extension Load {
    static func serverInfo() throws -> ServerInfo {
        try decoder.decode(SessionPayloadEnvelope<ServerInfo>.self, from: Fixture.data("server_info")).payload
    }

    static func agents() throws -> FetchAgentsRequest.Response {
        try decoder.decode(SessionPayloadEnvelope<FetchAgentsRequest.Response>.self, from: Fixture.data("fetch_agents_response")).payload
    }

    static func sendMessage() throws -> SendAgentMessageRequest.Response {
        try decoder.decode(SessionPayloadEnvelope<SendAgentMessageRequest.Response>.self, from: Fixture.data("send_agent_message_response")).payload
    }

    static func subscription() throws -> SetAgentTimelineSubscriptionRequest.Response {
        try decoder.decode(
            SessionPayloadEnvelope<SetAgentTimelineSubscriptionRequest.Response>.self,
            from: Fixture.data("set_subscription_response")
        ).payload
    }

    static func fixtureAgentId() throws -> String {
        try #require(agents().entries.first?.agent.id)
    }
}

/// Polls `condition` on the main actor until it holds, failing after `timeout`.
@MainActor
func eventually(
    timeout: Duration = .seconds(1),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Lets a test hold a request open, check the store mid-flight, then release it.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

/// Awaits a non-throwing test task with a timeout. Returns `nil` instead of hanging forever.
func awaitValue<T: Sendable>(
    _ task: Task<T, Never>, timeout: Duration = .seconds(10)
) async -> T? {
    let (results, continuation) = AsyncStream.makeStream(
        of: T?.self, bufferingPolicy: .unbounded)
    let waiter = Task {
        continuation.yield(await task.value)
        continuation.finish()
    }
    let timer = Task {
        do {
            try await Task.sleep(for: timeout)
        } catch {
            return
        }
        task.cancel()
        continuation.yield(nil)
        continuation.finish()
    }
    defer {
        waiter.cancel()
        timer.cancel()
    }
    for await result in results {
        return result
    }
    return nil
}
