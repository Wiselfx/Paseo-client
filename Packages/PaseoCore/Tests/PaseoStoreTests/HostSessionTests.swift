import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct HostSessionTests {
    @Test func startLoadsAgentsAndFollowsStates() async throws {
        let client = FakeDaemonClient()
        let agents = try Load.agents()
        client.onFetchAgents { _ in agents }

        let session = HostSession(client: client)
        await session.start()

        #expect(session.agents.count == 1)
        #expect(session.agents.first?.id == agents.entries.first?.agent.id)
        #expect(session.agentsError == nil)

        let info = try Load.serverInfo()
        client.push(.connected(info))
        let followedState = await eventually { session.connection == .connected(info) }
        #expect(followedState)
        #expect(session.serverInfo == info)
    }

    @Test func openingAConversationSubscribesAndLoadsTheTail() async throws {
        let client = FakeDaemonClient()
        let agents = try Load.agents()
        let agentId = try Load.fixtureAgentId()
        let page = try Load.page()
        let subscription = try Load.subscription()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { _ in page }
        client.onSetSubscription { _ in subscription }

        let session = HostSession(client: client)
        await session.start()

        let store = session.conversation(for: agentId)
        let ready = await eventually { store.phase == .ready }
        #expect(ready)
        #expect(store.turns.count == 2)
        #expect(store.agent?.id == agentId)
        #expect(session.conversation(for: agentId) === store, "same instance while open")

        let subscriptions = client.requests(SetAgentTimelineSubscriptionRequest.self)
        #expect(subscriptions.contains { $0.agentIds.contains(agentId) })

        let timelineRequests = client.requests(FetchAgentTimelineRequest.self)
        let tail = timelineRequests.first { $0.direction == .tail }
        #expect(tail?.agentId == agentId)
        #expect(tail?.limit == 40)
    }

    @Test func closingAConversationUnsubscribesIt() async throws {
        let client = FakeDaemonClient()
        let agents = try Load.agents()
        let agentId = try Load.fixtureAgentId()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }

        let session = HostSession(client: client)
        await session.start()

        _ = session.conversation(for: agentId)
        let subscribed = await eventually {
            client.requests(SetAgentTimelineSubscriptionRequest.self).contains { $0.agentIds.contains(agentId) }
        }
        #expect(subscribed)

        session.closeConversation(agentId)
        let unsubscribed = await eventually {
            let subscriptions = client.requests(SetAgentTimelineSubscriptionRequest.self)
            guard let last = subscriptions.last else { return false }
            return !last.agentIds.contains(agentId)
        }
        #expect(unsubscribed)
    }

    @Test func reconnectResubscribesAndCatchesUp() async throws {
        let client = FakeDaemonClient()
        let agents = try Load.agents()
        let agentId = try Load.fixtureAgentId()
        let info = try Load.serverInfo()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { request in
            guard request.direction == .after else { return try Load.page() }
            var response = try Load.page()
            response.direction = .after
            response.entries = []
            response.hasNewer = false
            return response
        }
        client.onSetSubscription { _ in try Load.subscription() }

        client.push(.connected(info))
        let session = HostSession(client: client)
        await session.start()
        _ = await eventually { session.connection == .connected(info) }

        let store = session.conversation(for: agentId)
        _ = await eventually { store.phase == .ready }
        #expect(store.timeline.endCursor?.seq == 22)

        let timelineRequests = client.requests(FetchAgentTimelineRequest.self).count
        let subscriptions = client.requests(SetAgentTimelineSubscriptionRequest.self).count

        let reconnecting = ConnectionState.reconnecting(attempt: 1, lastError: .timeout)
        client.push(reconnecting)
        _ = await eventually { session.connection == reconnecting }
        client.push(.connected(info))

        let caughtUp = await eventually {
            client.requests(FetchAgentTimelineRequest.self).contains {
                $0.direction == .after && $0.cursor?.seq == 22 && $0.limit == 0
            }
        }
        #expect(caughtUp)
        #expect(client.requests(FetchAgentTimelineRequest.self).count > timelineRequests)

        let resubscribed = await eventually {
            client.requests(SetAgentTimelineSubscriptionRequest.self).count > subscriptions
        }
        #expect(resubscribed)
        #expect(session.connection == .connected(info))
    }

    @Test func agentUpdatesReorderAndRemove() async throws {
        let client = FakeDaemonClient()
        let agents = try Load.agents()
        let original = try #require(agents.entries.first?.agent)
        client.onFetchAgents { _ in agents }

        let session = HostSession(client: client)
        client.push(.connected(try Load.serverInfo()))
        await session.start()
        _ = await eventually { session.agents.count == 1 }

        var newer = original
        newer.id = "agent-newer"
        newer.updatedAt = "2026-11-08T21:10:00.000Z"
        client.push(.agentUpdate(.upsert(newer, project: nil)))

        let movedToFront = await eventually { session.agents.first?.id == newer.id }
        #expect(movedToFront)
        #expect(session.agents.count == 2)

        client.push(.agentUpdate(.remove(agentId: newer.id)))
        let removed = await eventually { !session.agents.contains { $0.id == newer.id } }
        #expect(removed)
        #expect(session.agents.map(\.id) == [original.id])
    }
}
