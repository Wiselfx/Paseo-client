#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → Agents → Agent profiles: the host-wide named launch bundles. List, add, edit,
/// reorder, delete. Persisted by writing the whole list to the daemon config's `agentProfiles`
/// key (the same mechanism the upstream client uses), and only on daemons advertising
/// `features.agentProfiles`. Applying a profile at creation time is not wired yet; see the
/// PARITY row for the follow-up.
struct AgentProfilesSection: View {
    let session: HostSession

    @State private var editing: ProfileEditTarget?
    @State private var pendingDelete: AgentProfile?

    var body: some View {
        Group {
            if session.hostSettings.supportsProfiles {
                sectionContent
            } else {
                SettingsSectionLabel(title: "Agent profiles")
                RowGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Not available on this host")
                            .font(.paseo(.body))
                        Text("This host runs a daemon that does not support agent profiles yet.")
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.md)
                    .frame(minHeight: 52)
                }
            }
        }
        .sheet(item: $editing) { target in
            AgentProfileEditSheet(session: session, target: target)
        }
        .confirmationDialog(
            "Delete profile?",
            item: $pendingDelete,
            titleVisibility: .visible
        ) { profile in
            Button("Delete \(profile.name)", role: .destructive) {
                remove(profile)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the profile from this host. Agents already created are not affected.")
        }
    }

    // MARK: List

    @ViewBuilder private var sectionContent: some View {
        SettingsSectionLabel(title: "Agent profiles")
        RowGroup {
            if profiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No profiles yet.")
                        .font(.paseo(.body))
                    Text("Bundle provider, model, mode, thinking and a note into a named profile you can start an agent from.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.md)
                .frame(minHeight: 52, alignment: .leading)
            } else {
                ForEach(profiles.enumerated(), id: \.element.id) { index, profile in
                    AgentProfileRow(
                        profile: profile,
                        catalog: session.agentControl,
                        isFirst: index == 0,
                        isLast: index == profiles.count - 1,
                        onMove: { move(profile: profile, offset: $0) },
                        onEdit: { editing = ProfileEditTarget(mode: .edit, profile: profile) },
                        onDelete: { pendingDelete = profile }
                    )
                    if index < profiles.count - 1 { RowDivider() }
                }
            }
            RowDivider()
            AddProfileRow {
                editing = ProfileEditTarget(mode: .create, profile: nil)
            }
        }
        if let error = session.hostSettings.error {
            Text(error)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.failureInk)
                .padding(.leading, Space.lg)
        }
        Text("Stored on this host, not on this device.")
            .font(.paseo(.footnote))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, Space.lg)
    }

    private var profiles: [AgentProfile] { session.hostSettings.profiles }

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
}
#endif
