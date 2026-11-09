import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

/// Pins the T12 wire shapes against traffic captured by `Tools/capture-attachments-search.mjs`.
@Suite
struct AttachmentsSearchWireTests {
    private func payload<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<T>.self, from: Fixture.attachmentsSearch(name)
        ).payload
    }

    private func messageJSON<R: PaseoRequest>(_ request: R) throws -> [String: Any] {
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["message"] as? [String: Any])
    }

    // MARK: Upload

    @Test func uploadedFileResponseDecodes() throws {
        let response = try payload("file_upload_response", as: FileUploadRequest.Response.self)
        let file = try #require(response.file)
        #expect(file.type == "uploaded_file")
        #expect(file.fileName == "t12-fixture-upload.txt")
        #expect(file.mimeType == "text/plain")
        #expect(file.size == 48)
        #expect(!file.path.isEmpty)
        #expect(response.error == nil)
    }

    @Test func fileUploadRequestEncodesTheJsonFrameOnly() throws {
        let request = FileUploadRequest(
            fileName: "note.txt", mimeType: "text/plain", size: 12,
            modifiedAt: "2026-11-08T23:17:55.000Z")
        let message = try messageJSON(request)
        #expect(message["type"] as? String == "file.upload.request")
        #expect(message["fileName"] as? String == "note.txt")
        #expect(message["mimeType"] as? String == "text/plain")
        #expect(message["size"] as? Int == 12)
        #expect(message["modifiedAt"] as? String == "2026-11-08T23:17:55.000Z")
        #expect(message["data"] == nil, "bytes never ride on the JSON frame")
    }

    // MARK: Sending attachments

    @Test func sendRequestCarriesImagesAndStructuredAttachments() throws {
        let file = AgentAttachment.UploadedFileAttachment(
            id: "upload-1", fileName: "note.txt", mimeType: "text/plain", size: 12,
            path: "/tmp/fixture-sandbox/note.txt")
        let request = SendAgentMessageRequest(
            agentId: "agent-1", text: "see attached", messageId: "m-1",
            images: [ImageAttachment(data: Data([1, 2, 3]), mimeType: "image/png")],
            attachments: [
                .uploadedFile(file),
                .text(.init(text: "fixture body", title: "Fixture")),
            ])
        let message = try messageJSON(request)
        let images = try #require(message["images"] as? [[String: Any]])
        #expect(images.count == 1)
        #expect(images[0]["data"] as? String == "AQID")
        #expect(images[0]["mimeType"] as? String == "image/png")
        let attachments = try #require(message["attachments"] as? [[String: Any]])
        #expect(attachments.count == 2)
        #expect(attachments[0]["type"] as? String == "uploaded_file")
        #expect(attachments[0]["path"] as? String == "/tmp/fixture-sandbox/note.txt")
        #expect(attachments[1]["type"] as? String == "text")
        #expect(attachments[1]["text"] as? String == "fixture body")
    }

    @Test func sendRequestOmitsEmptyAttachmentFields() throws {
        let message = try messageJSON(SendAgentMessageRequest(agentId: "agent-1", text: "plain"))
        #expect(message["images"] == nil)
        #expect(message["attachments"] == nil)
    }

    @Test func structuredAttachmentsDecodeEveryKindAndKeepUnknowns() throws {
        let json = #"""
            [
              {"type":"forge_change_request","mimeType":"application/paseo-forge-change-request","number":7,"title":"PR","url":"https://example.test/7"},
              {"type":"forge_issue","mimeType":"application/paseo-forge-issue","number":8,"title":"Issue","url":"https://example.test/8"},
              {"type":"github_pr","mimeType":"application/github-pr","number":9,"title":"Legacy PR","url":"https://example.test/9"},
              {"type":"github_issue","mimeType":"application/github-issue","number":10,"title":"Legacy issue","url":"https://example.test/10"},
              {"type":"text","mimeType":"text/plain","text":"hello"},
              {"type":"review","mimeType":"application/paseo-review","cwd":"/tmp/x","mode":"uncommitted","comments":[]},
              {"type":"uploaded_file","id":"u","fileName":"f","mimeType":"text/plain","size":1,"path":"/tmp/f"},
              {"type":"future_attachment","payload":{"x":1}}
            ]
            """#
        let attachments = try JSONDecoder().decode([AgentAttachment].self, from: Data(json.utf8))
        #expect(attachments.count == 8)
        #expect(attachments.map(\.type) == [
            "forge_change_request", "forge_issue", "github_pr", "github_issue", "text", "review",
            "uploaded_file", "future_attachment",
        ])
        guard case .unknown(let type, let raw) = attachments[7] else {
            Issue.record("an unknown attachment kind must be kept, not dropped")
            return
        }
        #expect(type == "future_attachment")
        #expect(raw["payload"]?["x"] == .number(1))
        #expect(attachments[6].uploadedFile?.fileName == "f")
    }

    // MARK: Search

    @Test func timelineSearchResponseDecodesLocations() throws {
        let response = try payload(
            "agent_timeline_search_response", as: AgentTimelineSearchRequest.Response.self)
        #expect(!response.agentId.isEmpty)
        #expect(!response.epoch.isEmpty)
        #expect(response.locations.map(\.role) == [.user, .assistant])
        #expect(response.locations.count == 2)
        #expect(response.locations[0].seq < response.locations[1].seq)
        #expect(response.locations.allSatisfy { $0.count == 1 })
        #expect(response.nextCursor == nil)
        #expect(response.error == nil)
    }

    @Test func timelineSearchRequestEncodesCursorOnlyWhenPresent() throws {
        let first = try messageJSON(
            AgentTimelineSearchRequest(agentId: "agent-1", query: "ready"))
        #expect(first["type"] as? String == "agent.timeline.search.request")
        #expect(first["query"] as? String == "ready")
        #expect(first["cursor"] == nil)

        let next = try messageJSON(
            AgentTimelineSearchRequest(agentId: "agent-1", query: "ready", cursor: 42))
        #expect(next["cursor"] as? Int == 42)
    }

    @Test func unknownSearchRolesAndMissingCountsDoNotThrow() throws {
        let json = #"""
            {"requestId":"r","agentId":"a","epoch":"e","nextCursor":3,
             "locations":[{"seq":4,"role":"system"}],"error":null}
            """#
        let response = try JSONDecoder().decode(
            AgentTimelineSearchRequest.Response.self, from: Data(json.utf8))
        #expect(response.locations.first?.role == .unknown("system"))
        #expect(response.locations.first?.count == nil)
        #expect(response.nextCursor == 3)
    }

    // MARK: Subagents

    @Test func providerSubagentListResponseDecodes() throws {
        let response = try payload(
            "provider_subagents_list_response", as: ProviderSubagentListRequest.Response.self)
        #expect(response.subagents.isEmpty, "the captured sandbox agent has no provider children")
        #expect(!response.parentAgentId.isEmpty)
        #expect(response.error == nil)
    }

    @Test func providerSubagentUpdatesDecodeUpsertRemoveAndUnknownKinds() throws {
        let upsertJSON = #"""
            {"type":"session","message":{"type":"agent.provider_subagents.update","payload":{
              "kind":"upsert","subagent":{"id":"sub-1","parentAgentId":"parent-1",
              "parentSubagentId":"nested-1","provider":"claude","title":"Child",
              "description":"does work","status":"running","createdAt":"2026-11-08T20:00:00Z",
              "updatedAt":"2026-11-08T20:00:01Z","toolCallId":"call-1","cwd":"/tmp/fixture-sandbox",
              "subtitle":"2 tools"}}}}
            """#
        let upsert = try JSONDecoder().decode(
            SessionPayloadEnvelope<ProviderSubagentUpdate>.self, from: Data(upsertJSON.utf8)
        ).payload
        guard case .upsert(let subagent) = upsert.kind else {
            Issue.record("expected an upsert, got \(upsert.kind)")
            return
        }
        #expect(subagent.id == "sub-1")
        #expect(subagent.parentAgentId == "parent-1")
        #expect(subagent.parentSubagentId == "nested-1")
        #expect(subagent.status == .running)
        #expect(subagent.subtitle == "2 tools")

        let removeJSON = #"""
            {"type":"session","message":{"type":"agent.provider_subagents.update","payload":{
              "kind":"remove","parentAgentId":"parent-1","subagentId":"sub-1"}}}
            """#
        let remove = try JSONDecoder().decode(
            SessionPayloadEnvelope<ProviderSubagentUpdate>.self, from: Data(removeJSON.utf8)
        ).payload
        guard case .remove(let removal) = remove.kind else {
            Issue.record("expected a remove, got \(remove.kind)")
            return
        }
        #expect(removal.subagentId == "sub-1")

        let unknownJSON = #"""
            {"type":"session","message":{"type":"agent.provider_subagents.update","payload":{
              "kind":"reordered","subagentId":"sub-1"}}}
            """#
        let unknown = try JSONDecoder().decode(
            SessionPayloadEnvelope<ProviderSubagentUpdate>.self, from: Data(unknownJSON.utf8)
        ).payload
        guard case .unknown(let kind) = unknown.kind else {
            Issue.record("expected an unknown update kind, got \(unknown.kind)")
            return
        }
        #expect(kind == "reordered")
    }

    @Test func unknownSubagentStatusesDoNotThrow() throws {
        let json = #"""
            {"id":"s","parentAgentId":"p","provider":"x","title":null,"description":null,
             "status":"paused","createdAt":"2026-11-08T20:00:00Z",
             "updatedAt":"2026-11-08T20:00:01Z","toolCallId":null}
            """#
        let subagent = try JSONDecoder().decode(ProviderSubagent.self, from: Data(json.utf8))
        #expect(subagent.status == .unknown("paused"))
        #expect(subagent.parentSubagentId == nil)
        #expect(subagent.cwd == nil)
    }

    @Test func timelineSearchAndProviderSubagentsAreGatedTogether() throws {
        let info = try payload("server_info", as: ServerInfo.self)
        #expect(info.hasFeature("providerSubagents"))
        #expect(info.hasFeature("agentHistorySearch"))
    }
}
