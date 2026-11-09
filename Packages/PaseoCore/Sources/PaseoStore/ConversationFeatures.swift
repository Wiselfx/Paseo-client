import Foundation
import PaseoProtocol

// M8c: provider `AgentFeature`s on the open conversation — optimistic set with rollback,
// mirroring the `setMode`/`setThinking` idiom in `ConversationStore`.

extension ConversationStore {
    /// Sets one feature. Optimistic: the value changes locally, the daemon's `agent_update`
    /// settles it; on failure or rejection the previous features are restored and
    /// `actionError` is set. Selects only accept a value out of the feature's own option list.
    public func setFeature(featureId: String, value: JSONValue) async {
        guard let client else { return }
        guard var snapshot = agent, let features = snapshot.features else {
            actionError = "This agent doesn't offer that feature."
            return
        }
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            actionError = "This agent doesn't offer that feature."
            return
        }
        let before = snapshot
        guard let updated = features[index].applying(value: value) else {
            actionError = "That value doesn't fit this feature."
            return
        }
        snapshot.features?[index] = updated
        agent = snapshot
        do {
            let response = try await client.send(
                SetAgentFeatureRequest(agentId: agentId, featureId: featureId, value: value))
            if let error = response.error ?? (response.accepted ? nil : "The daemon rejected the change.") {
                agent = before
                actionError = error
                return
            }
            actionError = nil
            lastNotice = response.notice
        } catch {
            agent = before
            actionError = conversationErrorText(error)
        }
    }

    /// Toggles a toggle-kind feature.
    public func setFeatureToggle(featureId: String, value: Bool) async {
        await setFeature(featureId: featureId, value: .bool(value))
    }

    /// Selects an option id (or clears it with nil) on a select-kind feature.
    public func setFeatureSelection(featureId: String, value: String?) async {
        await setFeature(featureId: featureId, value: value.map(JSONValue.string) ?? .null)
    }
}
