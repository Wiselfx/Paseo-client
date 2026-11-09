import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// T12: sending a message with inline images and structured file attachments.
@Suite @MainActor
struct ConversationAttachmentsTests {
    private func makeStore() -> (ConversationStore, FakeDaemonClient, Gate) {
        let client = FakeDaemonClient()
        let gate = Gate()
        client.onFetchAgents { _ in try Load.agents() }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        client.onSendMessage { _ in
            await gate.wait()
            return try Load.sendMessage()
        }
        let store = ConversationStore(agentId: "agent-1", client: client)
        return (store, client, gate)
    }

    private var file: AgentAttachment.UploadedFileAttachment {
        .init(
            id: "upload-1", fileName: "note.txt", mimeType: "text/plain", size: 12,
            path: "/tmp/fixture-sandbox/note.txt")
    }

    @Test func attachmentsRideOnTheSendAndShowAPendingBubble() async throws {
        let (store, client, gate) = makeStore()
        store.draft = "see attached"
        let image = ImageAttachment(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png")

        let sending = Task {
            await store.sendWithAttachments(
                "see attached", images: [image],
                attachments: [.uploadedFile(file), .text(.init(text: "fixture body"))])
        }

        #expect(await eventually { store.timeline.rows.contains { $0.isPending } })
        #expect(store.draft.isEmpty)
        #expect(store.turns.last?.userMessage?.isPending == true)

        let recorded = await eventually { !client.requests(SendAgentMessageRequest.self).isEmpty }
        #expect(recorded)
        let request = try #require(client.requests(SendAgentMessageRequest.self).first)
        #expect(request.agentId == "agent-1")
        #expect(request.text == "see attached")
        #expect(request.messageId?.isEmpty == false)
        #expect(request.images?.count == 1)
        #expect(request.images?.first?.mimeType == "image/png")
        #expect(request.attachments?.map(\.type) == ["uploaded_file", "text"])
        #expect(request.attachments?.first?.uploadedFile?.path == "/tmp/fixture-sandbox/note.txt")

        await gate.open()
        #expect(await awaitValue(sending) != nil)
        #expect(store.actionError == nil)
        #expect(store.timeline.rows.contains { $0.isPending }, "stays until the daemon echoes it")
    }

    @Test func attachmentOnlyMessagesAreAllowed() async throws {
        let (store, client, gate) = makeStore()

        let sending = Task {
            await store.sendWithAttachments("", attachments: [.uploadedFile(file)])
        }
        #expect(await eventually { !client.requests(SendAgentMessageRequest.self).isEmpty })
        let request = try #require(client.requests(SendAgentMessageRequest.self).first)
        #expect(request.text.isEmpty)
        #expect(request.attachments?.count == 1)

        await gate.open()
        #expect(await awaitValue(sending) != nil)
    }

    @Test func anEmptyMessageWithoutAttachmentsIsIgnored() async throws {
        let (store, client, _) = makeStore()
        await store.sendWithAttachments("   ")
        #expect(client.requests(SendAgentMessageRequest.self).isEmpty)
        #expect(!store.timeline.rows.contains { $0.isPending })
    }

    @Test func aRejectedSendRollsBackAndRestoresTheDraft() async throws {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        client.onSendMessage { _ in
            try JSONDecoder().decode(
                SendAgentMessageRequest.Response.self,
                from: Data(
                    #"{"requestId":"r","agentId":"agent-1","accepted":false,"error":"too large"}"#.utf8))
        }
        let store = ConversationStore(agentId: "agent-1", client: client)
        store.draft = "see attached"

        await store.sendWithAttachments("see attached", attachments: [.uploadedFile(file)])

        #expect(!store.timeline.rows.contains { $0.isPending })
        #expect(store.draft == "see attached")
        #expect(store.actionError == "too large")
    }
}
