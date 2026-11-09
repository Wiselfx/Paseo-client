import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

/// Wire coverage for import session (`fetch_recent_provider_sessions_*`, `import_agent_request`
/// → `status`): request envelope shape and scrubbed-fixture response decode.
@Suite struct ImportSessionWireTests {
    private func messageJSON<R: PaseoRequest>(_ request: R) throws -> [String: Any] {
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["type"] as? String == "session")
        return try #require(root["message"] as? [String: Any])
    }

    @Test func listRequestEncodesScopeProvidersLimitAndQuery() throws {
        let message = try messageJSON(
            FetchRecentProviderSessionsRequest(
                cwd: "/tmp/fixture-sandbox", providers: ["pi"], limit: 15, query: "flaky"))
        #expect(message["type"] as? String == "fetch_recent_provider_sessions_request")
        #expect(message["cwd"] as? String == "/tmp/fixture-sandbox")
        #expect(message["providers"] as? [String] == ["pi"])
        #expect(message["limit"] as? Int == 15)
        #expect(message["query"] as? String == "flaky")
        #expect(message.keys.contains("requestId"))
    }

    @Test func listResponseDecodesFromFixture() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<FetchRecentProviderSessionsRequest.Response>.self,
            from: Fixture.importSession("fetch_recent_provider_sessions_response")).payload
        #expect(response.entries.count == 2)
        #expect(response.entries[0].id == "pi:fixture-handle-1")
        #expect(response.entries[0].cwd == "/tmp/fixture-sandbox")
        #expect(response.entries[0].title == "Fix the flaky test")
        #expect(response.entries[1].title == nil)
        #expect(response.filteredAlreadyImportedCount == 0)
    }

    @Test func importRequestUsesHandleIdentity() throws {
        let message = try messageJSON(
            ImportAgentRequest(
                providerId: "pi", providerHandleId: "fixture-handle-1",
                cwd: "/tmp/fixture-sandbox", workspaceId: "wks_fixture"))
        #expect(message["type"] as? String == "import_agent_request")
        #expect(message["providerId"] as? String == "pi")
        #expect(message["providerHandleId"] as? String == "fixture-handle-1")
        #expect(message["workspaceId"] as? String == "wks_fixture")
        #expect(message["provider"] == nil)
        #expect(message["sessionId"] == nil)
    }

    @Test func importResumedStatusDecodesTheAgent() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<ImportAgentRequest.Response>.self,
            from: Fixture.importSession("import_agent_resumed_status")).payload
        #expect(response.status == "agent_resumed")
        #expect(response.agent?.id == "fixture-imported-agent-1")
        #expect(response.agent?.cwd == "/tmp/fixture-sandbox")
        #expect(response.error == nil)
    }

    @Test func importFailedStatusDecodesTheError() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<ImportAgentRequest.Response>.self,
            from: Fixture.importSession("import_agent_failed_status")).payload
        #expect(response.status == "agent_create_failed")
        #expect(response.agent == nil)
        #expect(response.error == "session not found on host")
    }
}
