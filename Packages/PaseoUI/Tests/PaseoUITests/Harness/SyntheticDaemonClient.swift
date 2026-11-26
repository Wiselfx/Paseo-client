import Foundation
import PaseoKit
import PaseoProtocol

/// Stands in for the daemon: it answers the timeline fetch with one prepared page and nothing else.
/// Every other request fails the way an unreachable daemon would, which the stores tolerate.
final class SyntheticDaemonClient: DaemonClient, @unchecked Sendable {
    struct Unanswered: Error { let request: String }

    let events: AsyncStream<DaemonEvent>
    let states: AsyncStream<ConnectionState>
    private let page: FetchAgentTimelineRequest.Response

    init(page: FetchAgentTimelineRequest.Response) {
        let (events, _) = AsyncStream<DaemonEvent>.makeStream()
        let (states, _) = AsyncStream<ConnectionState>.makeStream()
        self.events = events
        self.states = states
        self.page = page
    }

    func send<R: PaseoRequest>(_ request: R, timeout: Duration) async throws -> R.Response {
        guard request is FetchAgentTimelineRequest, let typed = page as? R.Response else {
            throw Unanswered(request: R.type)
        }
        return typed
    }

    func initiate<R: PaseoRequest>(_ request: R, timeout: Duration) async throws -> InitiatedResponse<R> {
        InitiatedResponse(requestId: request.requestId) { try await self.send(request, timeout: timeout) }
    }

    func send<M: PaseoOutboundMessage>(_ message: M) async throws {}

    func send(binary: Data) async throws {}
}
