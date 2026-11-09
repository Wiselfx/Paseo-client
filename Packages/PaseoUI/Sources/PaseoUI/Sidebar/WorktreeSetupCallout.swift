#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The quiet "Set up worktree scripts" callout shown under a project that has worktree
/// workspaces but no `worktree.setup` in its `paseo.json` (M2.11's `ProjectConfigStore`, read
/// through a throwaway probe — see `ProjectSetupProbe`).
///
/// Hidden until the probe answers; a failed read stays quiet (the probe caches `failed`).
/// Tapping the body opens the M2.11 Project page; the xmark dismisses it, persisted per
/// project in `@AppStorage("paseo.sidebar.setupCalloutDismissed")`.
///
/// Mirrors upstream's `worktree-setup-callout-source` policy: git project, no setup commands,
/// dismissal key per project. Shown in the project (grouped) sidebar only — the date grouping
/// has no project headers to sit under.
extension PaseoSidebar {
    @ViewBuilder func worktreeSetupCallout(_ group: WorkspaceGroup) -> some View {
        if shouldShowWorktreeSetupCallout(group) {
            HStack(spacing: 8) {
                Button {
                    Haptics.selection()
                    sheet = .project(group.project)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "terminal")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                            .frame(width: 26, height: 26)
                            .background(ClaudePalette.chip, in: .circle)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Set up worktree scripts")
                                .font(typography.sans(13, weight: .medium))
                                .foregroundStyle(ClaudePalette.secondaryInk)
                                .lineLimit(1)
                            Text("Add setup commands so new worktrees can prepare themselves.")
                                .font(typography.sans(11))
                                .foregroundStyle(ClaudePalette.captionInk)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set up worktree scripts. Opens the project page.")
                Button {
                    Haptics.selection()
                    dismissWorktreeSetupCallout(group.project.projectId)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(ClaudePalette.chip.opacity(0.55), in: .rect(cornerRadius: 8))
            .padding(.top, 4)
        }
    }

    func shouldShowWorktreeSetupCallout(_ group: WorkspaceGroup) -> Bool {
        guard group.project.projectKind == .git else { return false }
        let hasWorktree = session.workspaceDirectory.workspaces.contains {
            $0.projectId == group.project.projectId && $0.workspaceKind == .worktree
        }
        guard hasWorktree else { return false }
        guard !setupCalloutDismissedProjects.contains(group.project.projectId) else { return false }
        return session.projectSetupProbe.hasSetupCommands[group.project.projectRootPath] == false
    }

    var setupCalloutDismissedProjects: Set<String> {
        Set(
            setupCalloutDismissed
                .split(separator: ",")
                .map(String.init)
                .filter { !$0.isEmpty })
    }

    func dismissWorktreeSetupCallout(_ projectId: String) {
        var set = setupCalloutDismissedProjects
        set.insert(projectId)
        setupCalloutDismissed = set.sorted().joined(separator: ",")
    }
}
#endif
