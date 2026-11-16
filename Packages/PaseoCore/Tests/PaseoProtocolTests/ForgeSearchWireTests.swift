import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

/// Wire coverage for forge search (`forge.search.request`, legacy `github_search_request`):
/// request envelope shape, fixture decode, kind normalization and tolerant items.
@Suite struct ForgeSearchWireTests {
    private func messageJSON<R: PaseoRequest>(_ request: R) throws -> [String: Any] {
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["type"] as? String == "session")
        return try #require(root["message"] as? [String: Any])
    }

    @Test func forgeRequestEncodesCwdQueryLimitAndKinds() throws {
        let message = try messageJSON(
            ForgeSearchRequest(cwd: "/tmp/fixture-sandbox", query: "flaky", limit: 20, kinds: ["change_request"]))
        #expect(message["type"] as? String == "forge.search.request")
        #expect(message["cwd"] as? String == "/tmp/fixture-sandbox")
        #expect(message["query"] as? String == "flaky")
        #expect(message["limit"] as? Int == 20)
        #expect(message["kinds"] as? [String] == ["change_request"])
    }

    @Test func legacyRequestUsesTheLegacyType() throws {
        let message = try messageJSON(GitHubSearchRequest(cwd: "/tmp/fixture-sandbox", query: "flaky"))
        #expect(message["type"] as? String == "github_search_request")
    }

    @Test func forgeResponseDecodesFromFixture() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<ForgeSearchRequest.Response>.self,
            from: Fixture.forgeSearch("forge_search_response")).payload
        #expect(response.items.count == 2)
        #expect(response.items[0].kind == .changeRequest)
        #expect(response.items[0].number == 42)
        #expect(response.items[0].id == "change_request:42")
        #expect(response.items[1].kind == .issue)
        #expect(response.authState?.stringValue == "authenticated")
        #expect(response.error == nil)
    }

    @Test func legacyKindsNormalizeToTheNeutralPair() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<GitHubSearchRequest.Response>.self,
            from: Fixture.forgeSearch("github_search_response")).payload
        #expect(response.items.map(\.kind) == [.changeRequest, .issue])
        #expect(response.featuresEnabled == true)
    }

    @Test func oneBadItemDoesNotSinkTheList() throws {
        let json = """
        {"type":"session","message":{"type":"forge.search.response","payload":{
          "requestId":"r","authState":"some_future_state","items":[
            {"kind":"issue","number":1,"title":"Good","url":"https://example.invalid/1","state":"open","labels":[]},
            {"kind":"issue","number":"not-a-number","title":"Also good","url":"https://example.invalid/2","state":"open","labels":[]},
            42
          ],"error":null}}}
        """
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<ForgeSearchRequest.Response>.self,
            from: Data(json.utf8)).payload
        // The non-object item is dropped; the string-number item decodes with no number.
        #expect(response.items.count == 2)
        #expect(response.items[1].number == nil)
        #expect(ForgeAuthState(raw: response.authState?.stringValue) == .unknown("some_future_state"))
    }

    @Test func itemBecomesTheForgeNeutralAttachment() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<ForgeSearchRequest.Response>.self,
            from: Fixture.forgeSearch("forge_search_response")).payload
        #expect(
            response.items[0].asAttachment == .forgeChangeRequest(
                AgentAttachment.ForgeChangeRequestAttachment(
                    forge: "github", number: 42, title: "Fix the flaky test",
                    url: "https://example.invalid/sandbox/fixture/pull/42",
                    body: "The sandbox suite flakes on rerun.", projectPath: "sandbox/fixture",
                    baseRefName: "main", headRefName: "fix-flaky")))
        #expect(
            response.items[1].asAttachment == .forgeIssue(
                AgentAttachment.ForgeIssueAttachment(
                    forge: nil, number: 7, title: "Document the sandbox flow",
                    url: "https://example.invalid/sandbox/fixture/issues/7")))
    }
}
