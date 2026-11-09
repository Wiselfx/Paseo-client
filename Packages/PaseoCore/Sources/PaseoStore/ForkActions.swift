import Foundation
import PaseoKit
import PaseoProtocol

// M7h: fork the conversation up to a point into a new agent.
//
// `agent.fork_context.request` (gate `features.agentForkContext`, checked view-side) returns
// the curated history as a `text` attachment with `contextKind: "chat_history"`; a plain
// `create_agent_request` carrying that attachment seeds the fork. The boundary is always a
// cursor pinned to a projected row's `seqEnd` — `boundaryMessageId` only matches assistant
// messages upstream.
//
// The fork copies provider, cwd, mode, model and thinking from the source snapshot; provider
// feature values are not carried over (the snapshot doesn't advertise them — the daemon applies
// defaults).

extension HostSession {
    /// `server_info.features.agentForkContext`. Exposed to views as one plain flag.
    public var isForkContextSupportedByHost: Bool {
        serverInfo?.hasFeature("agentForkContext") ?? false
    }
}

extension ConversationStore {
    /// Forks this conversation up to and including `boundarySeq` and seeds a new agent with the
    /// result. Returns the new agent's id, or nil with an error message.
    public func forkConversation(fromBoundarySeq boundarySeq: Int) async -> (agentId: String?, error: String?) {
        guard let client else {
            return (nil, "This conversation is not connected to a daemon.")
        }
        guard let agent else {
            return (nil, "The agent's info hasn't loaded yet.")
        }
        guard let epoch = timeline.epoch else {
            return (nil, "The conversation hasn't loaded yet.")
        }
        do {
            let context = try await client.send(
                ForkContextRequest(
                    agentId: agentId,
                    boundaryCursor: TimelineCursor(epoch: epoch, seq: boundarySeq)))
            if let message = context.error {
                return (nil, message)
            }
            guard let attachment = context.attachment else {
                return (nil, "Fork returned no chat history.")
            }
            let created = try await client.send(
                CreateAgentRequest(
                    config: AgentSessionConfig(
                        provider: agent.provider, cwd: agent.cwd, modeId: agent.currentModeId,
                        model: agent.model, thinkingOptionId: agent.thinkingOptionId),
                    workspaceId: agent.workspaceId,
                    attachments: [.text(attachment)]))
            guard created.status == "agent_created" else {
                return (nil, created.error ?? "The daemon could not create the fork.")
            }
            guard let createdId = created.agent?.id ?? created.agentId else {
                return (nil, "The daemon created the fork but did not return its id.")
            }
            return (createdId, nil)
        } catch {
            return (nil, paseoStoreErrorText(error))
        }
    }
}
