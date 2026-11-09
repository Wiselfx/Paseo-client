import Foundation
import PaseoKit
import PaseoProtocol

// T12 additions to ConversationStore. Kept out of HostSession.swift so parallel tickets only see
// a stored property and one routing line there.

extension ConversationStore {
    /// Sends text with inline images and/or structured attachments. Shows the same optimistic
    /// bubble as `send(_:)`; attachments alone (empty text) are allowed.
    ///
    /// File attachments must already exist on the daemon (`uploaded_file`); the byte upload is a
    /// separate `file.upload.request` + binary-frame flow.
    public func sendWithAttachments(
        _ text: String, images: [ImageAttachment] = [], attachments: [AgentAttachment] = []
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty || !attachments.isEmpty, let client else { return }

        let clientId = UUID().uuidString
        showPendingSend(
            text: trimmed, clientId: clientId, timestamp: Self.nowTimestamp())
        if !trimmed.isEmpty, trimmed == draft.trimmingCharacters(in: .whitespacesAndNewlines) {
            draft = ""
        }

        do {
            let response = try await client.send(
                SendAgentMessageRequest(
                    agentId: agentId,
                    text: trimmed,
                    messageId: clientId,
                    activeTurnBehavior: isRunning ? "steer" : nil,
                    images: images.isEmpty ? nil : images,
                    attachments: attachments.isEmpty ? nil : attachments))
            if response.accepted {
                markSendAccepted()
            } else {
                rollBackSend(
                    clientId: clientId, text: trimmed,
                    error: response.error ?? "The daemon rejected the message.")
            }
        } catch {
            rollBackSend(clientId: clientId, text: trimmed, error: conversationErrorText(error))
        }
    }

    /// Called once per `server_info` and when a conversation opens.
    internal func update(serverInfo info: ServerInfo?) {
        subagents.update(serverInfo: info)
    }

    /// Routes one unsolicited message; ignores types and parents that are not ours.
    internal func handleSubagentUpdate(messageType: String, raw: Data) {
        _ = subagents.handle(messageType: messageType, raw: raw)
    }

    /// Provider subagent updates are not replayed, so refetch after a reconnect.
    internal func reloadSubagents() async {
        await subagents.load()
    }
}

extension HostSession {
    /// Paseo-managed subagents: ordinary, non-archived agents labelled with this parent id.
    /// Provider-managed children are `ConversationStore.subagents.items` instead; they have no
    /// agent rows and no lifecycle actions.
    public func subagents(of parentAgentId: String) -> [AgentSnapshot] {
        agents.filter { $0.labels?["paseo.parent-agent-id"] == parentAgentId }
    }
}
