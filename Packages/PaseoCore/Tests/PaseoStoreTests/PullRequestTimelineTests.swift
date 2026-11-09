import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct PullRequestTimelineTests {
    private func response(_ fixture: String) throws -> PullRequestTimelineRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<PullRequestTimelineRequest.Response>.self,
            from: Fixture.data(fixture, in: "pr-timeline"))
            .payload
    }

    // MARK: Fixture decoding

    @Test func timelineDecodesTheHandWrittenFixture() throws {
        let response = try response("pr_timeline_response")
        #expect(response.items.count == 5)
        #expect(response.truncated == false)
        #expect(response.error == nil)
        #expect(response.prNumber == 12)

        let reviews = response.items.compactMap { item -> PullRequestTimelineReview? in
            if case .review(let review) = item { return review }
            return nil
        }
        #expect(reviews.count == 1)
        let review = try #require(reviews.first)
        #expect(review.id == "review-1")
        #expect(review.reviewState == .approved)
        #expect(review.author == "alice")
        #expect(review.createdAt == 1730976000000)

        let comments = response.items.compactMap { item -> PullRequestTimelineComment? in
            if case .comment(let comment) = item { return comment }
            return nil
        }
        #expect(comments.count == 3)
        let inline = try #require(comments.first { $0.id == "comment-1" })
        #expect(inline.reviewId == "review-1")
        #expect(inline.threadId == "thread-1")
        #expect(inline.location?.path == "Packages/PaseoCore/Sources/PaseoStore/TimelineState.swift")
        #expect(inline.location?.line == 42)
        let plain = try #require(comments.first { $0.id == "comment-3" })
        #expect(plain.reviewId == nil)
        #expect(plain.location == nil)
    }

    @Test func unknownItemKindsSurviveAsUnknown() throws {
        let response = try response("pr_timeline_response")
        let unknowns = response.items.compactMap { item -> String? in
            if case .unknown(let kind) = item { return kind }
            return nil
        }
        #expect(unknowns == ["emoji_reaction"])
    }

    @Test func forbiddenErrorDecodesAsTypedError() throws {
        let response = try response("pr_timeline_forbidden_response")
        let error = try #require(response.error)
        #expect(error.kind == .forbidden)
        #expect(error.message == "Resource not accessible by integration")
        #expect(response.items.isEmpty)
    }

    // MARK: Store behavior

    private func gitActions(client: FakeDaemonClient) throws -> (PullRequestTimelineStore, WorkspaceGitExtras) {
        var workspace = try Load.sandboxWorkspace()
        workspace.workspaceDirectory = "/tmp/fixture-sandbox"
        workspace.projectRootPath = "/tmp/fixture-sandbox"
        let checkout = CheckoutStore(workspace: workspace, client: client)
        let extras = WorkspaceGitExtras(
            workspaceId: workspace.id, cwd: workspace.cwd, checkout: checkout, client: client)
        let store = PullRequestTimelineStore(
            workspaceId: workspace.id, cwd: workspace.cwd, client: client)
        return (store, extras)
    }

    @Test func loadStoresItemsFromTheDaemon() async throws {
        let client = FakeDaemonClient()
        let data = try Fixture.data("pr_timeline_response", in: "pr-timeline")
        client.on(PullRequestTimelineRequest.self) { request in
            #expect(request.prNumber == 12)
            #expect(request.repoOwner == "getpaseo")
            #expect(request.repoName == "paseo")
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<PullRequestTimelineRequest.Response>.self, from: data).payload
        }
        let (store, _) = try gitActions(client: client)
        await store.load(prNumber: 12, repoOwner: "getpaseo", repoName: "paseo")
        #expect(store.items.count == 5)
        #expect(store.error == nil)
        #expect(store.isLoading == false)
        #expect(store.truncated == false)
    }

    @Test func loadMapsForbiddenToObservableError() async throws {
        let client = FakeDaemonClient()
        let data = try Fixture.data("pr_timeline_forbidden_response", in: "pr-timeline")
        client.on(PullRequestTimelineRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<PullRequestTimelineRequest.Response>.self, from: data).payload
        }
        let (store, _) = try gitActions(client: client)
        await store.load(prNumber: 12, repoOwner: "getpaseo", repoName: "paseo")
        #expect(store.items.isEmpty)
        #expect(store.error?.kind == .forbidden)
    }

    @Test func loadWithoutForgeFactsMakesNoRequests() async throws {
        let client = FakeDaemonClient()
        let (store, _) = try gitActions(client: client)
        await store.load(prNumber: 12, repoOwner: nil, repoName: nil)
        #expect(store.items.isEmpty)
        #expect(store.error?.kind == .unknown)
        #expect(client.requests(PullRequestTimelineRequest.self).isEmpty)
    }

    @Test func timelineIsMemoizedPerCheckout() throws {
        let client = FakeDaemonClient()
        var workspace = try Load.sandboxWorkspace()
        workspace.workspaceDirectory = "/tmp/fixture-sandbox"
        workspace.projectRootPath = "/tmp/fixture-sandbox"
        let checkout = CheckoutStore(workspace: workspace, client: client)
        let gitExtras = GitExtrasStore(client: client)
        let first = gitExtras.timeline(for: checkout)
        let second = gitExtras.timeline(for: checkout)
        #expect(first === second)
    }
}
