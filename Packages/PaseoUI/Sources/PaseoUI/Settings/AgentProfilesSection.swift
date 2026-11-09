#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Settings → Agents → Agent profiles: the host-wide named launch bundles. List, add, edit,
/// reorder, delete. Persisted by writing the whole list to the daemon config's `agentProfiles`
/// key (the same mechanism the upstream client uses), and only on daemons advertising
/// `features.agentProfiles`. Applying a profile at creation time is not wired yet; see the
/// PARITY row for the follow-up.
struct AgentProfilesSection: View {
    let session: HostSession

    @State private var editing: ProfileEditTarget?
    @State private var pendingDelete: AgentProfile?

    private let typography = ClaudeTypography()

    var body: some View {
        Group {
            if session.hostSettings.supportsProfiles {
                sectionContent
            } else {
                sectionLabel("Agent profiles")
                RowGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Not available on this host")
                            .font(.system(size: 17))
                        Text("Profiles need the daemon's agentProfiles feature.")
                            .font(.system(size: 13))
                            .foregroundStyle(ClaudePalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 52)
                }
            }
        }
        .sheet(item: $editing) { target in
            AgentProfileEditSheet(session: session, target: target)
        }
        .confirmationDialog(
            "Delete profile?",
            isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let profile = pendingDelete {
                Button("Delete \(profile.name)", role: .destructive) {
                    remove(profile)
                    pendingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes the profile from this host. Agents already created are not affected.")
        }
    }

    // MARK: List

    @ViewBuilder private var sectionContent: some View {
        sectionLabel("Agent profiles")
        RowGroup {
            if profiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No profiles yet.")
                        .font(.system(size: 17))
                    Text("Bundle provider, model, mode, thinking and a note into a named profile you can start an agent from.")
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 52, alignment: .leading)
            } else {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    profileRow(profile, index: index)
                    if index < profiles.count - 1 { RowDivider() }
                }
            }
            RowDivider()
            addRow
        }
        if let error = session.hostSettings.error {
            Text(error)
                .font(.system(size: 13))
                .foregroundStyle(ClaudePalette.failureInk)
                .padding(.leading, 16)
        }
        Text("Stored host-wide on this daemon, not on this device.")
            .font(.system(size: 13))
            .foregroundStyle(ClaudePalette.secondary)
            .padding(.leading, 16)
    }

    private var profiles: [AgentProfile] { session.hostSettings.profiles }

    private func profileRow(_ profile: AgentProfile, index: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(.system(size: 17))
                        .lineLimit(1)
                        .accessibilityIdentifier("settings.profiles.name.\(profile.id)")
                    Text(summary(for: profile))
                        .font(typography.mono(11, relativeTo: .caption))
                        .foregroundStyle(ClaudePalette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let notes = profile.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions(profile: profile, index: index)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(minHeight: 56)
    }

    private func actions(profile: AgentProfile, index: Int) -> some View {
        HStack(spacing: 0) {
            moveButton(profile: profile, offset: -1, isFirst: index == 0)
            moveButton(profile: profile, offset: 1, isLast: index == profiles.count - 1)
            Button {
                Haptics.selection()
                editing = ProfileEditTarget(mode: .edit, profile: profile)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 17, weight: .light))
                    .frame(width: 38, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(profile.name)")
            .accessibilityIdentifier("settings.profiles.edit.\(profile.id)")
            Button {
                Haptics.selection()
                pendingDelete = profile
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .frame(width: 38, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(profile.name)")
            .accessibilityIdentifier("settings.profiles.delete.\(profile.id)")
        }
    }

    private func moveButton(profile: AgentProfile, offset: Int, isFirst: Bool = false, isLast: Bool = false) -> some View {
        Button {
            Haptics.selection()
            move(profile: profile, offset: offset)
        } label: {
            Image(systemName: offset < 0 ? "chevron.up" : "chevron.down")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle((isFirst || isLast) ? ClaudePalette.secondary.opacity(0.4) : ClaudePalette.secondary)
                .frame(width: 34, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isFirst || isLast)
        .accessibilityLabel(offset < 0 ? "Move \(profile.name) up" : "Move \(profile.name) down")
        .accessibilityIdentifier("settings.profiles.move.\(offset < 0 ? "up" : "down").\(profile.id)")
    }

    private var addRow: some View {
        Button {
            Haptics.selection()
            editing = ProfileEditTarget(mode: .create, profile: nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(ClaudePalette.ink)
                Text("Add profile")
                    .font(.system(size: 17))
                    .foregroundStyle(ClaudePalette.ink)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.profiles.add")
    }

    // MARK: Mutations

    private func move(profile: AgentProfile, offset: Int) {
        var next = profiles
        guard let index = next.firstIndex(where: { $0.id == profile.id }) else { return }
        let target = index + offset
        guard target >= 0, target < next.count else { return }
        next.swapAt(index, target)
        Task { _ = await session.hostSettings.saveProfiles(next) }
    }

    private func remove(_ profile: AgentProfile) {
        Task { _ = await session.hostSettings.saveProfiles(profiles.filter { $0.id != profile.id }) }
    }

    // MARK: Summary line

    private func summary(for profile: AgentProfile) -> String {
        var parts = [profile.provider]
        if let model = profile.model, !model.isEmpty {
            parts.append(modelName(profile.provider, model))
        }
        if let modeId = profile.modeId, !modeId.isEmpty,
            let mode = modeLabel(profile.provider, modeId) {
            parts.append(mode)
        }
        if let thinkingId = profile.thinkingOptionId, !thinkingId.isEmpty {
            parts.append(thinkingLabel(profile.provider, model: profile.model, optionId: thinkingId))
        }
        return parts.joined(separator: " · ")
    }

    private func modelName(_ providerID: String, _ modelID: String) -> String {
        session.agentControl.models(forProvider: providerID).first { $0.id == modelID }?.label ?? modelID
    }

    private func modeLabel(_ providerID: String, _ modeId: String) -> String? {
        session.agentControl.modes(forProvider: providerID).first { $0.id == modeId }?.label ?? modeId
    }

    private func thinkingLabel(_ providerID: String, model: String?, optionId: String) -> String {
        let effectiveModel = model ?? session.agentControl.defaultModel(forProvider: providerID)?.id
        let options = effectiveModel.map {
            session.agentControl.thinkingOptions(forProvider: providerID, modelId: $0)
        } ?? []
        return options.first { $0.id == optionId }?.label ?? optionId
    }

    // MARK: Shared bits

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15))
            .foregroundStyle(ClaudePalette.secondary)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }
}

/// Which edit sheet to present and with what.
struct ProfileEditTarget: Identifiable {
    enum Mode: Equatable { case create, edit }

    let mode: Mode
    let profile: AgentProfile?

    init(mode: Mode, profile: AgentProfile?) {
        self.mode = mode
        self.profile = profile
    }

    var id: String {
        switch mode {
        case .create: "create"
        case .edit: "edit.\(profile?.id ?? "unknown")"
        }
    }
}
#endif
