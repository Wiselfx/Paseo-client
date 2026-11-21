#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The live checkout-PR card (C13): title, branches, state pill, and the check counts with the
/// review decision. Shown when a GitHub link points at the workspace's own PR; tapping opens the
/// PR pane.
struct GitHubPRCard: View {
    let pr: CheckoutPrStatus
    let url: String
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let counts = checkCounts(pr.checks)
        let resolution = reviewText(pr.reviewDecision)
        Button(action: onOpen) {
            PaseoCard(content:
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "arrow.triangle.pull")
                            .font(.glyph(.regular, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.title)
                                .font(.paseo(.callout))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                            Text("#\(pr.number ?? 0) · \(pr.headRefName) → \(pr.baseRefName)")
                                .font(.paseo(.caption))
                                .foregroundStyle(Palette.secondaryInk)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        StatePill(prStateLabel, tone: prStateTone)
                    }
                    HStack(spacing: Space.sm) {
                        CheckDot(count: counts.passed, color: Palette.successInk)
                        CheckDot(count: counts.failed, color: Palette.failureInk)
                        CheckDot(count: counts.pending, color: Palette.tertiaryInk)
                        if let resolution {
                            Text(resolution)
                                .font(.paseo(.caption))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.glyph(.small, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryInk)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(checksSummary(counts, resolution: resolution))
                }
                .contentShape(.rect))
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .paseoCardMenu(
            openTitle: "Open pull request",
            onOpen: onOpen,
            copyTitle: "Copy link",
            copyText: url,
            externalTitle: "Open on GitHub",
            externalURL: URL(string: url))
        .paseoCardAccessibility(
            kind: "Pull request", title: pr.title,
            meta: "#\(pr.number ?? 0) \(prStateLabel)", isButton: true)
    }

    private struct CheckCounts: Equatable {
        var passed = 0
        var failed = 0
        var pending = 0
    }

    /// Passed / failed / pending from the checkout's check states.
    private func checkCounts(_ checks: [CheckoutPrCheck]) -> CheckCounts {
        var counts = CheckCounts()
        for check in checks {
            switch check.status.lowercased() {
            case "success", "passed", "pass", "neutral", "skipped":
                counts.passed += 1
            case "failure", "failed", "fail", "error", "timed_out", "action_required":
                counts.failed += 1
            default:
                counts.pending += 1
            }
        }
        return counts
    }

    /// The spoken checks row, joined with the locale's list punctuation.
    private func checksSummary(_ counts: CheckCounts, resolution: String?) -> String {
        var parts = ["\(counts.passed) passed", "\(counts.failed) failed", "\(counts.pending) pending"]
        if let resolution { parts.append(resolution) }
        return parts.formatted(.list(type: .and, width: .narrow))
    }

    /// Upstream wording (`en.ts` pull-request states): Open, Draft, Merged, Closed.
    private var prStateLabel: String {
        if pr.isMerged { return "Merged" }
        if pr.isDraft == true { return "Draft" }
        return switch pr.state.lowercased() {
        case "closed": "Closed"
        default: "Open"
        }
    }

    private var prStateTone: StatePill.Tone {
        if pr.isMerged { return .success }
        if pr.isDraft == true { return .neutral }
        return switch pr.state.lowercased() {
        case "closed": .failure
        default: .success
        }
    }

    /// The review decision in the card's words (upstream `activity.*`, en.ts).
    private func reviewText(_ decision: String?) -> String? {
        switch decision?.lowercased() {
        case "approved": "Approved"
        case "changes_requested": "Changes requested"
        case "commented": "Commented"
        case "review_required": "Review required"
        default: nil
        }
    }
}
#endif
