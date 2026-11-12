#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - RichGitHubCard (G9 C7, C13)

// NOTE: RemoteImagePipeline/G9: the most common links a coding agent prints. A
// `github.com` URL parses to owner/repo/kind; the card then resolves, in order:
// a checkout PR with the same number becomes the live PR card (bound to the
// checkout's PR status, updating live); a same-repo sibling resolves its title and
// state through forge search; anything else degrades to the plain link card.

/// What forge search found for a same-repo sibling link.
struct GitHubLinkInfo: Sendable, Equatable {
    var title: String
    var state: String
    var labels: [String] = []
}

/// A GitHub PR, issue, commit or run link: the row card with a `StatePill`, or the
/// live checkout-PR card when the number matches the workspace's PR.
struct RichGitHubCard: View {
    let url: String
    let parsed: GitHubURL

    @Environment(\.openURL) private var openURL
    @Environment(\.richActions) private var richActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSafari = false
    @State private var info: GitHubLinkInfo?
    @State private var lookedUp = false

    /// The checkout's PR, mirrored by the conversation controller. Nil outside one.
    private var checkoutPR: CheckoutPrStatus? { richActions?.checkoutPR }

    /// The workspace's PR when this link points at it (number match; repo match when
    /// both sides name one). That card is live (C13); everything else is a snapshot.
    private var matchedPR: CheckoutPrStatus? {
        guard case .pull(let number) = parsed.kind,
            let pr = checkoutPR, pr.number == number
        else { return nil }
        if let owner = pr.repoOwner, let name = pr.repoName,
            owner.lowercased() != parsed.owner.lowercased()
                || name.lowercased() != parsed.repo.lowercased()
        {
            return nil
        }
        return pr
    }

    private var linkTitle: String {
        if let info { return info.title }
        return "\(parsed.slug)\(kindSuffix)"
    }

    private var kindSuffix: String {
        switch parsed.kind {
        case .repo: ""
        case .pull(let n): " #\(n)"
        case .issue(let n): " #\(n)"
        case .commit(let sha): " @\(String(sha.prefix(7)))"
        case .actionsRun(let id): " run \(id)"
        }
    }

    private var linkMeta: String {
        "github.com · \(parsed.slug)\(kindSuffix)"
    }

    private var glyph: String {
        switch parsed.kind {
        case .pull: "arrow.branch"
        case .issue: "circle"
        case .commit: "number"
        case .actionsRun: "play.circle"
        case .repo: "folder"
        }
    }

    var body: some View {
        if let matchedPR {
            prCard(matchedPR)
        } else if let info {
            linkedRow(title: info.title, state: info.state)
        } else {
            RichLinkCard(url: url)
        }
    }

    /// One lookup per URL, through the controller's forge search — same repo only, and
    /// only when the checkout names its repo. Anything else degrades to the link card
    /// (a workspace-scoped search must never answer for a foreign repo).
    private var lookupKey: String? {
        guard matchedPR == nil, !lookedUp, sameRepo == true else { return nil }
        return url
    }

    /// Whether the link names the checkout's repo. Nil when the checkout names none:
    /// without a repo to match against, the card stays a link card.
    private var sameRepo: Bool? {
        guard let pr = checkoutPR, let owner = pr.repoOwner, let name = pr.repoName else {
            return nil
        }
        return owner.lowercased() == parsed.owner.lowercased()
            && name.lowercased() == parsed.repo.lowercased()
    }

    // MARK: Resolution

    @MainActor
    private func lookup() async {
        lookedUp = true
        // Same repo only, and only when the checkout names its repo: a
        // workspace-scoped search must never answer for a foreign repo.
        guard sameRepo == true, let lookup = richActions?.githubLookup else { return }
        guard let found = await lookup(parsed) else { return }
        guard !Task.isCancelled else { return }
        info = found
    }

    // MARK: The live PR card (C13)

    @ViewBuilder
    private func prCard(_ pr: CheckoutPrStatus) -> some View {
        let counts = checkCounts(pr.checks)
        let resolution = reviewText(pr.reviewDecision)
        Button {
            openPRPane()
        } label: {
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
                        StatePill(prStateLabel(pr), tone: prStateTone(pr))
                    }
                    HStack(spacing: Space.sm) {
                        checkDot(count: counts.passed, color: Palette.successInk)
                        checkDot(count: counts.failed, color: Palette.failureInk)
                        checkDot(count: counts.pending, color: Palette.tertiaryInk)
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
            onOpen: { openPRPane() },
            copyTitle: "Copy link",
            copyText: url,
            externalTitle: "Open on GitHub",
            externalURL: URL(string: url))
        .paseoCardAccessibility(
            kind: "Pull request", title: pr.title,
            meta: "#\(pr.number ?? 0) \(prStateLabel(pr))", isButton: true)
    }

    private func openPRPane() {
        richActions?.openPRPane()
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

    private func checkDot(count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("\(count)")
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .monospacedDigit()
        }
        .accessibilityHidden(count == 0)
    }

    private func checksSummary(_ counts: CheckCounts, resolution: String?) -> String {
        var parts = ["\(counts.passed) passed", "\(counts.failed) failed", "\(counts.pending) pending"]
        if let resolution { parts.append(resolution) }
        return parts.joined(separator: ", ")
    }

    /// Upstream wording (`en.ts` pull-request states): Open, Draft, Merged, Closed.
    private func prStateLabel(_ pr: CheckoutPrStatus) -> String {
        if pr.isMerged { return "Merged" }
        if pr.isDraft == true { return "Draft" }
        switch pr.state.lowercased() {
        case "closed": "Closed"
        default: "Open"
        }
    }

    private func prStateTone(_ pr: CheckoutPrStatus) -> StatePill.Tone {
        if pr.isMerged { return .success }
        if pr.isDraft == true { return .neutral }
        switch pr.state.lowercased() {
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

    // MARK: Same-repo siblings (C7)

    private func linkedRow(title: String, state: String) -> some View {
        Button {
            showSafari = true
        } label: {
            PaseoRowCard(
                glyph: glyph, title: title,
                meta: "\(parsed.slug) · \(stateLabel(state))",
                accessory: StatePill(stateLabel(state), tone: stateTone(state)))
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .paseoCardMenu(
            openTitle: "Open",
            onOpen: { showSafari = true },
            copyTitle: "Copy link",
            copyText: url,
            externalTitle: "Open on GitHub",
            externalURL: URL(string: url))
        .paseoCardAccessibility(
            kind: "GitHub link", title: title,
            meta: "\(parsed.slug) \(stateLabel(state))", isButton: true)
        .task(id: lookupKey) { await lookup() }
        .fullScreenCover(isPresented: $showSafari) {
            if let target = URL(string: url) {
                SafariView(url: target).ignoresSafeArea()
            }
        }
    }

    private func stateLabel(_ state: String) -> String {
        switch state.lowercased() {
        case "open": "Open"
        case "closed": "Closed"
        case "merged": "Merged"
        case "draft": "Draft"
        default: state
        }
    }

    private func stateTone(_ state: String) -> StatePill.Tone {
        switch state.lowercased() {
        case "open", "merged": .success
        case "closed": .failure
        default: .neutral
        }
    }
}
#endif
