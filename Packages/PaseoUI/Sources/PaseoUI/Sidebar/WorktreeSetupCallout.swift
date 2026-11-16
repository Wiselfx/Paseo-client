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
/// project in `SidebarPreferences.setupCalloutDismissed`.
///
/// Mirrors upstream's `worktree-setup-callout-source` policy: git project, no setup commands,
/// dismissal key per project. Shown in the project (grouped) sidebar only — the date grouping
/// has no project headers to sit under.
extension PaseoSidebar {
    @ViewBuilder func worktreeSetupCallout(_ group: WorkspaceGroup) -> some View {
        if shouldShowWorktreeSetupCallout(group) {
            HStack(spacing: 8) {
                Button {
                    sheet = .project(group.project)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "terminal")
                            .font(.glyph(.small, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryInk)
                            .frame(width: 26, height: 26)
                            .background(Palette.chip, in: .circle)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Set up worktree scripts")
                                .font(.paseo(.footnote, weight: .medium))
                                .foregroundStyle(Palette.secondaryInk)
                                .lineLimit(1)
                            Text("Add setup commands so new worktrees can prepare themselves.")
                                .font(.paseo(.caption2))
                                .foregroundStyle(Palette.captionInk)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set up worktree scripts. Opens the project page.")
                Button {
                    dismissWorktreeSetupCallout(group.project.projectId)
                } label: {
                    Image(systemName: "xmark")
                        .font(.glyph(.small, weight: .regular))
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(width: 30, height: 30)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Palette.chip.opacity(0.55), in: .rect(cornerRadius: Radius.sm))
            .padding(.top, 4)
        }
    }

    func shouldShowWorktreeSetupCallout(_ group: WorkspaceGroup) -> Bool {
        guard group.project.projectKind == .git else { return false }
        let hasWorktree = session.workspaceDirectory.workspaces.contains {
            $0.projectId == group.project.projectId && $0.workspaceKind == .worktree
        }
        guard hasWorktree else { return false }
        guard !preferences.isSetupCalloutDismissed(projectId: group.project.projectId) else {
            return false
        }
        return session.projectSetupProbe.hasSetupCommands[group.project.projectRootPath] == false
    }

    func dismissWorktreeSetupCallout(_ projectId: String) {
        preferences.dismissSetupCallout(projectId: projectId)
    }
}
#endif
