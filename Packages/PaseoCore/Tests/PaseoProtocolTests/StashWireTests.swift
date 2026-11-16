import Foundation
import PaseoProtocol
import Testing

/// Wire coverage for stash & switch (`stash_save_request`, `stash_pop_request`,
/// `stash_list_request`; `Upstream: packages/protocol/src/messages.ts:2678-2700,6310-6345`).
@Suite struct StashWireTests {
    private func messageJSON<R: PaseoRequest>(_ request: R) throws -> [String: Any] {
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["type"] as? String == "session")
        return try #require(root["message"] as? [String: Any])
    }

    private func payload<P: Decodable & Sendable>(_ json: String, as type: P.Type) throws -> P {
        try JSONDecoder().decode(SessionPayloadEnvelope<P>.self, from: Data(json.utf8)).payload
    }

    @Test func saveEncodesCwdAndBranchTag() throws {
        let message = try messageJSON(
            StashSaveRequest(cwd: "/tmp/fixture-sandbox", branch: "feature/t11"))
        #expect(message["type"] as? String == "stash_save_request")
        #expect(message["cwd"] as? String == "/tmp/fixture-sandbox")
        #expect(message["branch"] as? String == "feature/t11")
    }

    @Test func saveOmitsAnAbsentBranch() throws {
        let message = try messageJSON(StashSaveRequest(cwd: "/tmp/fixture-sandbox"))
        #expect(message["branch"] == nil, "the schema has branch optional; absent, not null")
    }

    @Test func popEncodesTheIndex() throws {
        let message = try messageJSON(StashPopRequest(cwd: "/tmp/fixture-sandbox", stashIndex: 2))
        #expect(message["type"] as? String == "stash_pop_request")
        #expect(message["stashIndex"] as? Int == 2)
    }

    @Test func listAsksForPaseoStashes() throws {
        let message = try messageJSON(StashListRequest(cwd: "/tmp/fixture-sandbox", paseoOnly: true))
        #expect(message["type"] as? String == "stash_list_request")
        #expect(message["paseoOnly"] as? Bool == true)
    }

    @Test func listResponseDecodesEntries() throws {
        let json = """
        {"type":"session","message":{"type":"stash_list_response","payload":{
          "cwd":"/tmp/fixture-sandbox","requestId":"r","error":null,
          "entries":[
            {"index":0,"message":"paseo-auto-stash: feature/t11","branch":"feature/t11",
             "isPaseo":true},
            {"index":1,"message":"wip","branch":null,"isPaseo":false}
          ]}}}
        """
        let payload = try payload(json, as: StashListRequest.Response.self)
        #expect(payload.entries.count == 2)
        #expect(payload.entries[0].index == 0)
        #expect(payload.entries[0].branch == "feature/t11")
        #expect(payload.entries[0].isPaseo)
        #expect(payload.entries[1].branch == nil)
        #expect(payload.error == nil)
    }

    @Test func saveFailureKeepsTheDaemonError() throws {
        let json = """
        {"type":"session","message":{"type":"stash_save_response","payload":{
          "cwd":"/tmp/fixture-sandbox","success":false,"requestId":"r",
          "error":{"code":"NOT_GIT_REPO","message":"Not a git repository"}}}}
        """
        let payload = try payload(json, as: StashSaveRequest.Response.self)
        #expect(payload.success == false)
        #expect(payload.error?.code == .notGitRepo)
        #expect(payload.error?.message == "Not a git repository")
    }

    @Test func popResponseDecodes() throws {
        let json = """
        {"type":"session","message":{"type":"stash_pop_response","payload":{
          "cwd":"/tmp/fixture-sandbox","success":true,"error":null,"requestId":"r"}}}
        """
        let payload = try payload(json, as: StashPopRequest.Response.self)
        #expect(payload.success)
        #expect(payload.error == nil)
    }
}
