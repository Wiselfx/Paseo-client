#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The detail page's Target rows: the new-agent config (workspace, provider, model, mode,
/// thinking), or the existing agent a heartbeat prompts.
struct ScheduleTargetRows: View {
    let session: HostSession
    let summary: ScheduleSummary

    var body: some View {
        if let config = summary.target.newAgentConfig {
            ScheduleInfoRow("Workspace", value: workspaceName(cwd: config.cwd), detail: config.cwd)
            ScheduleInfoRow("Provider", value: providerLabel(config.provider))
            ScheduleInfoRow("Model", value: modelLabel(provider: config.provider, model: config.model))
            if config.modeId != nil {
                ScheduleInfoRow("Mode", value: modeLabel(provider: config.provider, mode: config.modeId))
            }
            if config.thinkingOptionId != nil {
                ScheduleInfoRow(
                    "Thinking",
                    value: thinkingLabel(
                        provider: config.provider, model: config.model, thinking: config.thinkingOptionId))
            }
            if config.archiveOnFinish == true {
                ScheduleInfoRow("Archive on finish", value: "On")
            }
        } else {
            let agentId = summary.target.agentId
            ScheduleInfoRow(
                "Heartbeat",
                value: agentTitle(agentId),
                detail: agentId.map { "Agent ID: \($0)" })
            if let agentId,
                let workspaceId = session.agents.first(where: { $0.id == agentId })?.workspaceId,
                let workspace = session.workspaceDirectory.workspace(id: workspaceId)
            {
                ScheduleInfoRow("Workspace", value: workspace.name, detail: workspace.cwd)
            }
        }
    }

    private func workspaceName(cwd: String) -> String {
        for group in session.workspaceDirectory.groups {
            if let match = group.workspaces.first(where: { $0.cwd == cwd }) { return match.name }
        }
        return "Custom directory"
    }

    private func agentTitle(_ agentId: String?) -> String {
        guard let agentId else { return "Unknown agent" }
        return session.agents.first(where: { $0.id == agentId })?.title ?? agentId
    }

    private func providerLabel(_ providerId: String) -> String {
        session.agentControl.provider(providerId)?.label ?? providerId
    }

    private func modelLabel(provider: String, model: String?) -> String {
        guard let model else { return "Provider default" }
        if let match = session.agentControl.models(forProvider: provider).first(where: { $0.id == model }) {
            return match.label
        }
        return model
    }

    private func modeLabel(provider: String, mode: String?) -> String {
        guard let mode else { return "Provider default" }
        return session.agentControl.modes(forProvider: provider).first(where: { $0.id == mode })?.label
            ?? mode
    }

    private func thinkingLabel(provider: String, model: String?, thinking: String?) -> String {
        guard let thinking else { return "Provider default" }
        if let modelId = model ?? session.agentControl.defaultModel(forProvider: provider)?.id {
            return session.agentControl.thinkingOptions(forProvider: provider, modelId: modelId)
                .first(where: { $0.id == thinking })?.label ?? thinking
        }
        return thinking
    }
}
#endif
