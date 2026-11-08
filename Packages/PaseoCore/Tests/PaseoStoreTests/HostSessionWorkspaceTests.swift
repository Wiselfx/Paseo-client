import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct HostSessionWorkspaceTests {
    private func makeSession() throws -> (HostSession, FakeDaemonClient, ServerInfo) {
        let client = FakeDaemonClient()
        let info = try Load.workspaceServerInfo()
        let agents = try Load.agents()
        let projects = try Load.projectList()
        let workspaces = try Load.workspaceDirectory()
        let status = try Load.checkoutStatus()
        let diff = try Load.checkoutDiff()

        client.on(FetchAgentsRequest.self) { _ in agents }
        client.on(ProjectListRequest.self) { _ in projects }
        client.on(FetchWorkspacesRequest.self) { _ in workspaces }
        client.on(CheckoutStatusRequest.self) { _ in status }
        client.on(CheckoutPrStatusRequest.self) { _ in
            throw FakeDaemonClient.FakeError.noHandler("checkout_pr_status_request")
        }
        client.on(SubscribeCheckoutDiffRequest.self) { _ in diff }
        client.on(SubscriptionReleaseRequest.self) { request in
            SubscriptionReleaseRequest.Response(
                requestId: request.requestId, subscriptionId: request.subscriptionId)
        }
        client.on(UnsubscribeCheckoutDiffRequest.self) { request in
            UnsubscribeCheckoutDiffRequest.Response(requestId: request.requestId)
        }

        client.push(.connected(info))
        let session = HostSession(client: client)
        return (session, client, info)
    }

    private func mutatedFixture(_ name: String, mutate: (inout [String: Any]) -> Void) throws -> Data {
        let data = try Fixture.data(name, in: "workspaces")
        guard
            var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            var message = root["message"] as? [String: Any],
            var payload = message["payload"] as? [String: Any]
        else {
            throw Fixture.FixtureError.missing(name)
        }
        mutate(&payload)
        message["payload"] = payload
        root["message"] = message
        return try JSONSerialization.data(withJSONObject: root)
    }

    @Test func routesWorkspaceStatusAndDiffEventsToStores() async throws {
        let (session, client, _) = try makeSession()
        await session.start()
        #expect(await eventually { session.workspaceDirectory.hasLoaded })
        #expect(session.workspaceDirectory.projects.count == 1)

        let workspace = try #require(session.workspaceDirectory.workspace(id: "wks_6adc97aa7e1e49e3"))
        let store = session.checkout(for: workspace)
        #expect(await eventually { store.phase == .ready && store.diffPhase == .ready })
        #expect(session.checkout(for: workspace) === store, "same instance while open")

        // A new workspace arrives over the directory subscription.
        client.push(
            .unhandled(
                messageType: "workspace_update",
                raw: try Fixture.data("workspace_update_02", in: "workspaces")))
        let createdId = try Load.workspaceCreate().workspace?.id ?? ""
        #expect(
            await eventually {
                session.workspaceDirectory.workspace(id: createdId) != nil
            })

        // A project update removes a project row.
        let projectRemove = """
            {"type":"session","message":{"type":"project.update","payload":{
              "kind":"remove","projectId":"prj_4d116e00cefb42d4"
            }}}
            """
        client.push(.unhandled(messageType: "project.update", raw: Data(projectRemove.utf8)))
        #expect(await eventually { session.workspaceDirectory.project(id: "prj_4d116e00cefb42d4") == nil })

        // A pushed status updates both the sidebar row and the open checkout.
        let statusData = try mutatedFixture("checkout_status_response") { payload in
            payload["currentBranch"] = "pushed/branch"
            payload["isDirty"] = false
        }
        client.push(.unhandled(messageType: "checkout_status_update", raw: statusData))
        #expect(await eventually { store.branch == "pushed/branch" })
        #expect(store.isDirty == false)
        #expect(
            await eventually {
                session.workspaceDirectory.workspace(id: workspace.id)?.branch == "pushed/branch"
            })

        // A pushed diff replaces the open snapshot.
        let diffData = try mutatedFixture("subscribe_checkout_diff_response") { payload in
            payload["files"] = []
        }
        client.push(.unhandled(messageType: "checkout_diff_update", raw: diffData))
        #expect(await eventually { store.filesChanged == 0 })

        await session.closeCheckout(workspace.id)
        #expect(client.requests(SubscriptionReleaseRequest.self).count >= 1)
        #expect(session.checkout(for: workspace) !== store, "a closed store is not reused")
    }

    @Test func reconnectReloadsDirectoryAndResubscribesCheckout() async throws {
        let (session, client, info) = try makeSession()
        await session.start()
        #expect(await eventually { session.workspaceDirectory.hasLoaded })

        let workspace = try #require(session.workspaceDirectory.workspace(id: "wks_6adc97aa7e1e49e3"))
        let store = session.checkout(for: workspace)
        #expect(await eventually { store.diffPhase == .ready })

        let fetches = client.requests(FetchWorkspacesRequest.self).count
        let subscriptions = client.requests(SubscribeCheckoutDiffRequest.self).count

        let reconnecting = ConnectionState.reconnecting(attempt: 1, lastError: .timeout)
        client.push(reconnecting)
        #expect(await eventually { session.connection == reconnecting })
        client.push(.connected(info))

        #expect(
            await eventually {
                client.requests(FetchWorkspacesRequest.self).count > fetches
            })
        #expect(
            await eventually {
                client.requests(SubscribeCheckoutDiffRequest.self).count > subscriptions
            })
        #expect(await eventually { store.diffPhase == .ready })
        #expect(session.connection == .connected(info))
    }

    @Test func closingAndReopeningACheckoutStartsAFreshStore() async throws {
        let (session, client, _) = try makeSession()
        await session.start()
        #expect(await eventually { session.workspaceDirectory.hasLoaded })
        let workspace = try #require(session.workspaceDirectory.workspace(id: "wks_6adc97aa7e1e49e3"))

        let first = session.checkout(for: workspace)
        #expect(await eventually { first.diffPhase == .ready })
        let subscribeCount = client.requests(SubscribeCheckoutDiffRequest.self).count

        await session.closeCheckout(workspace.id)
        let second = session.checkout(for: workspace)
        #expect(second !== first)
        #expect(await eventually { second.diffPhase == .ready })
        #expect(client.requests(SubscribeCheckoutDiffRequest.self).count > subscribeCount)
    }
}
