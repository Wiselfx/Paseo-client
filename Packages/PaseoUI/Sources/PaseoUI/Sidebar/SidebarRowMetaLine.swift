#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A row's second line: branch, diff stat, age, label chips, then the PR badge and script dots.
/// Its own view so a change here (ages, diff stats, PR state) does not re-run the title's body.
struct SidebarRowMetaLine: View {
    let model: SidebarRowModel

    private var hasVisibleDiffStat: Bool {
        guard model.showDiffStats, let stat = model.workspace.diffStat else { return false }
        return stat.additions > 0 || stat.deletions > 0
    }

    var body: some View {
        let workspace = model.workspace
        return HStack(spacing: 4) {
            if model.showBranch {
                Text(model.branchText)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if model.showDiffStats, let stat = workspace.diffStat, stat.additions > 0 || stat.deletions > 0 {
                if model.showBranch { Text("·").foregroundStyle(Palette.captionInk) }
                // The title gives way, the numbers never do (D3 §1).
                DiffStat(added: stat.additions, removed: stat.deletions, compact: true)
                    .fixedSize()
                    .layoutPriority(1)
                    .opacity(0.75)
            }
            if let age = model.ageText {
                if model.showBranch || hasVisibleDiffStat {
                    Text("·").foregroundStyle(Palette.captionInk)
                }
                Text(age)
                    .fixedSize()
                    .layoutPriority(1)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if !model.labelDefinitions.isEmpty {
                if model.showBranch || hasVisibleDiffStat || model.ageText != nil {
                    Text("·").foregroundStyle(Palette.captionInk)
                }
                WorkspaceLabelChips(definitions: model.labelDefinitions)
            }
            Spacer(minLength: 6)
            if model.showPRBadge, let pullRequest = workspace.githubRuntime?.pullRequest,
                let number = pullRequest.number
            {
                Text(verbatim: "#\(number)")
                    .font(.paseo(.caption2, weight: .semibold))
                    .foregroundStyle(Self.pullRequestTint(pullRequest))
            }
            if !model.scriptDots.isEmpty {
                HStack(spacing: 3) {
                    ForEach(0..<model.scriptDots.count, id: \.self) { index in
                        Circle()
                            .fill(model.scriptDots[index] == .running ? Palette.successInk : Palette.failureInk)
                            .frame(width: 5, height: 5)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(model.scriptDotsLabel)
            }
        }
        .font(.paseo(.caption))
        .lineLimit(1)
    }

    private static func pullRequestTint(_ pr: WorkspaceGitHubRuntime.WorkspacePullRequest) -> Color {
        if pr.isMerged { return Palette.unread }
        if pr.isDraft == true { return Palette.tertiaryInk }
        switch pr.state.lowercased() {
        case "open": return Palette.successInk
        case "closed": return Palette.failureInk
        default: return Palette.secondaryInk
        }
    }
}
#endif
