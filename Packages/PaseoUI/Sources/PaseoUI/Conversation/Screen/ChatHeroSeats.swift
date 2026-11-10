#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// M7i — the hero-menu pickers on the new-conversation hero: a workspace (directory) chip and an
/// agent-preset (profile) seat, so a chat can start without opening the full new-agent sheet.
///
/// The seat reuses M8f's profile picker semantics: a profile applies provider-at-creation fields
/// once, at start. Here it applies to this conversation in place — model, mode, thinking and
/// feature values — so it applies only to profiles whose provider is this agent's provider.
/// The workspace chip opens the directory-chip menu: picking another workspace starts a fresh
/// chat there (same provider/model/mode/thinking) and selects it — no new-agent sheet.
struct ClaudeHeroSeats: View {
    let session: HostSession
    @Bindable var store: ConversationStore
    let onOpenAgent: ((String) -> Void)?

    @State private var appliedProfileId: String?
    @State private var applyingProfile = false

    private var workspaces: [WorkspaceDescriptor] { session.workspaceDirectory.workspaces }

    private var currentWorkspace: WorkspaceDescriptor? {
        guard let id = store.agent?.workspaceId else { return nil }
        return session.workspaceDirectory.workspace(id: id)
    }

    /// Profiles this agent can apply: its own provider, offered by the host.
    private var applicableProfiles: [AgentProfile] {
        let current = store.agent?.provider
        return session.hostSettings.profiles.filter { profile in
            guard profile.provider == current else { return false }
            return session.agentControl.provider(profile.provider)?.isAvailable == true
        }
    }

    private var profileLabel: String {
        guard let appliedProfileId,
            let match = session.hostSettings.profiles.first(where: { $0.id == appliedProfileId })
        else { return "Profile" }
        return match.name
    }

    var body: some View {
        HStack(spacing: 10) {
            workspaceSeat
            profileSeat
        }
        .accessibilityIdentifier("hero.seats")
    }

    // MARK: Workspace (directory) chip

    private var workspaceSeat: some View {
        Menu {
            Section("Workspace") {
                ForEach(workspaces) { workspace in
                    Button {
                        switchWorkspace(workspace)
                    } label: {
                        Label(
                            workspace.name,
                            systemImage: workspace.id == currentWorkspace?.id ? "checkmark" : "folder")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                Text(currentWorkspace?.name ?? "Workspace")
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Palette.chip, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workspace, \(currentWorkspace?.name ?? "none")")
    }

    // MARK: Agent preset / profile seat

    private var profileSeat: some View {
        Menu {
            if applicableProfiles.isEmpty {
                Text("No profiles for this provider")
            } else {
                Section("Profile") {
                    ForEach(applicableProfiles) { profile in
                        Button {
                            apply(profile)
                        } label: {
                            Label(
                                profile.name,
                                systemImage: appliedProfileId == profile.id
                                    ? "checkmark" : "sparkles")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                Text(profileLabel)
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Palette.chip, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile, \(profileLabel)")
        .accessibilityIdentifier("hero.profileSeat")
    }

    // MARK: Actions

    /// Applies one profile to this conversation, in place: model, mode, thinking and feature
    /// values (skipping any that don't fit this agent).
    private func apply(_ profile: AgentProfile) {
        guard !applyingProfile else { return }
        applyingProfile = true
        Task {
            if let model = profile.model { await store.setModel(model) }
            if let mode = profile.modeId { await store.setMode(mode) }
            if let thinking = profile.thinkingOptionId { await store.setThinking(thinking) }
            if let featureValues = profile.featureValues {
                for (id, value) in featureValues {
                    let supported = store.agent?.features?.contains { feature in
                        feature.id == id
                    } ?? false
                    if supported { await store.setFeature(featureId: id, value: value) }
                }
            }
            appliedProfileId = profile.id
            applyingProfile = false
            Haptics.selection()
        }
    }

    /// Starts a fresh chat in `workspace` with this conversation's config, and selects it.
    private func switchWorkspace(_ workspace: WorkspaceDescriptor) {
        guard workspace.id != currentWorkspace?.id, !applyingProfile else { return }
        guard let agent = store.agent else { return }
        applyingProfile = true
        Task {
            let agentId = await session.agentControl.createAgent(
                cwd: workspace.cwd, workspaceId: workspace.id, provider: agent.provider,
                model: agent.model, modeId: agent.currentModeId,
                thinkingOptionId: agent.thinkingOptionId)
            applyingProfile = false
            guard let agentId else { return }
            await session.refreshAgents()
            onOpenAgent?(agentId)
            Haptics.selection()
        }
    }
}
#endif
