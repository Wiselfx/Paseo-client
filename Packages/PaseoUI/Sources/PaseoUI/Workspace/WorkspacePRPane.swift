#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The PR pane for the Changes page: title/number/state, review decision, checks with a rollup,
/// an "Open on <forge>" row, and the activity timeline (reviews and comments) with Add-to-chat
/// per review/comment. Renders nothing when the branch has no PR.
struct WorkspacePRSection: View {
    let session: HostSession
    let checkout: CheckoutStore
    private let typography = ClaudeTypography()

    @Environment(\.openURL) private var openURL
    @Environment(\.mentionInChat) private var mentionInChat

    /// The modern-diff helper; T11 PR facts live here.
    private var extras: WorkspaceGitExtras {
        session.gitExtras.workspace(for: checkout)
    }

    /// The PR timeline store; memoized per checkout by the extras store.
    private var timeline: PullRequestTimelineStore {
        session.gitExtras.timeline(for: checkout)
    }

    private var status: CheckoutPrStatus? { extras.prStatus ?? checkout.prStatus }

    var body: some View {
        if let status, !status.url.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Pull request")
                        .font(typography.sans(13, weight: .medium))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
                stateRow(status)
                if !status.checks.isEmpty { checksBlock(status) }
                openOnForgeRow(status)
                activityBlock(status)
                // Keep the section visually separate from the file list below it.
                ClaudeDivider()
            }
        }
    }

    // MARK: Header row + state pill

    private func stateRow(_ status: CheckoutPrStatus) -> some View {
        HStack(alignment: .top, spacing: 10) {
            StatePill(
                label: stateLabel(status),
                tint: stateTint(status))
            VStack(alignment: .leading, spacing: 4) {
                Text("#\(String(status.number ?? 0)) · \(status.title)")
                    .font(typography.sans(15, weight: .semibold))
                    .foregroundStyle(ClaudePalette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let decision = reviewDecisionLine(status) {
                    Text(decision)
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func stateLabel(_ status: CheckoutPrStatus) -> String {
        if status.isDraft == true { return "Draft" }
        switch status.state.uppercased() {
        case "OPEN": return "Open"
        case "MERGED": return "Merged"
        case "CLOSED": return "Closed"
        default: return status.state.capitalized
        }
    }

    private func stateTint(_ status: CheckoutPrStatus) -> Color {
        if status.isMerged { return ClaudePalette.unread }
        if status.isDraft == true { return ClaudePalette.secondaryInk }
        switch status.state.uppercased() {
        case "OPEN": return ClaudePalette.successInk
        case "CLOSED": return ClaudePalette.tertiaryInk
        default: return ClaudePalette.secondaryInk
        }
    }

    private func reviewDecisionLine(_ status: CheckoutPrStatus) -> String? {
        guard let decision = status.reviewDecision, !decision.isEmpty else { return nil }
        return "Review: \(decision.replacingOccurrences(of: "_", with: " ").capitalized)"
    }

    // MARK: Checks

    private func checksBlock(_ status: CheckoutPrStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Checks")
                .font(typography.sans(12, weight: .medium))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            ForEach(Array(status.checks.enumerated()), id: \.offset) { _, check in
                checkRow(check, prNumber: status.number ?? 0)
            }
            if let rollup = checksRollup(status.checks) {
                Text(rollup)
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 10)
    }

    private func checkRow(_ check: CheckoutPrCheck, prNumber: Int) -> some View {
        let failing = isFailing(check.status)
        let passing = isPassing(check.status)
        return Button {
            if let url = check.url, let target = URL(string: url) {
                openURL(target)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: passing ? "checkmark.circle.fill" : failing ? "xmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(passing ? ClaudePalette.successInk : failing ? ClaudePalette.failureInk : ClaudePalette.warning)
                VStack(alignment: .leading, spacing: 1) {
                    Text(check.name)
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    if let workflow = check.workflow, !workflow.isEmpty {
                        Text(workflow)
                            .font(typography.sans(11))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let duration = check.duration, !duration.isEmpty {
                    Text(duration)
                        .font(typography.mono(11))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(check.url == nil || check.url?.isEmpty == true)
        .accessibilityLabel("Check \(check.name), \(check.status)")
        .contextMenu {
            if mentionInChat != nil {
                Button("Add to chat") {
                    mentionInChat?(excerptForCheck(check, prNumber: prNumber))
                }
            }
        }
    }

    private func isPassing(_ status: String?) -> Bool {
        switch status?.lowercased() {
        case "success", "passed", "pass", "neutral", "skipped": return true
        default: return false
        }
    }

    private func isFailing(_ status: String?) -> Bool {
        switch status?.lowercased() {
        case "failure", "failed", "fail", "error", "cancelled", "canceled", "timed_out", "timedout",
            "startup_failure", "stale": return true
        default: return false
        }
    }

    private func checksRollup(_ checks: [CheckoutPrCheck]) -> String? {
        guard !checks.isEmpty else { return nil }
        let failing = checks.filter { isFailing($0.status) }.count
        let passing = checks.filter { isPassing($0.status) }.count
        let pending = checks.count - failing - passing
        var parts: [String] = []
        if failing > 0 { parts.append("\(failing) failing") }
        if pending > 0 { parts.append("\(pending) running") }
        if passing > 0 { parts.append("\(passing) passed") }
        return parts.joined(separator: " · ")
    }

    // MARK: Open on forge

    /// `.capitalized` turns "github" into "Github"; brand names keep their casing.
    private static func forgeName(_ raw: String?) -> String {
        switch (raw ?? "github").lowercased() {
        case "github": "GitHub"
        case "gitlab": "GitLab"
        default: (raw ?? "github").capitalized
        }
    }

    private func openOnForgeRow(_ status: CheckoutPrStatus) -> some View {
        let forge = Self.forgeName(status.forge)
        return Button {
            if let url = URL(string: status.url) { openURL(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                Text("Open on \(forge)")
                    .font(typography.sans(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                Spacer(minLength: 8)
                if let repoOwner = status.repoOwner, let repoName = status.repoName {
                    Text("\(repoOwner)/\(repoName)")
                        .font(typography.mono(11))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open on \(forge)")
    }

    // MARK: Activity timeline

    private var reviews: [PullRequestTimelineReview] {
        timeline.items.compactMap { if case .review(let review) = $0 { return review } else { return nil } }
    }

    private var comments: [PullRequestTimelineComment] {
        timeline.items.compactMap { if case .comment(let comment) = $0 { return comment } else { return nil } }
    }

    private var unknownItems: [String] {
        timeline.items.compactMap { if case .unknown(let kind) = $0 { return kind } else { return nil } }
    }

    private func nestedComments(of review: PullRequestTimelineReview) -> [PullRequestTimelineComment] {
        comments.filter { $0.reviewId == review.id }
    }

    private var standaloneComments: [PullRequestTimelineComment] {
        let reviewIds = Set(reviews.map(\.id))
        return comments.filter { comment in
            guard let reviewId = comment.reviewId else { return true }
            return !reviewIds.contains(reviewId)
        }
    }

    private func activityBlock(_ status: CheckoutPrStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Activity")
                    .font(typography.sans(12, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                Spacer(minLength: 8)
                if timeline.isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        Task { await loadTimeline(status) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                            .frame(width: 28, height: 28)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh timeline")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)

            if let error = timeline.error {
                errorRow(error)
            } else if reviews.isEmpty && standaloneComments.isEmpty && unknownItems.isEmpty {
                if !timeline.isLoading {
                    Text("No reviews yet.")
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
            } else {
                ForEach(reviews) { review in
                    reviewRow(review, prNumber: status.number ?? 0)
                    ForEach(nestedComments(of: review)) { comment in
                        commentRow(comment, prNumber: status.number ?? 0, indented: true)
                    }
                }
                ForEach(standaloneComments) { comment in
                    commentRow(comment, prNumber: status.number ?? 0, indented: false)
                }
                ForEach(unknownItems, id: \.self) { kind in
                    Text("Unsupported item · \(kind)")
                        .font(typography.mono(11))
                        .foregroundStyle(ClaudePalette.captionInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                if timeline.truncated {
                    Text("Only some items are shown.")
                        .font(typography.sans(11))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.bottom, 10)
    }

    private func errorRow(_ error: PullRequestTimelineError) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(ClaudePalette.failureInk)
            Text(error.message.isEmpty ? fallbackMessage(for: error.kind) : error.message)
                .font(typography.sans(12))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Retry") {
                Task { if let status { await loadTimeline(status) } }
            }
            .font(typography.sans(12, weight: .medium))
            .foregroundStyle(ClaudePalette.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityLabel("Timeline error")
    }

    private func fallbackMessage(for kind: PullRequestTimelineErrorKind) -> String {
        switch kind {
        case .notFound: "This PR is gone or your token can't see it."
        case .forbidden: "No permission to read this timeline."
        case .unknown: "The timeline is unavailable."
        }
    }

    private func loadTimeline(_ status: CheckoutPrStatus) async {
        await timeline.load(
            prNumber: status.number ?? 0, repoOwner: status.repoOwner, repoName: status.repoName)
    }

    // MARK: Timeline rows

    private func reviewRow(_ review: PullRequestTimelineReview, prNumber: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AuthorAvatar(author: review.author)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(review.author)
                        .font(typography.sans(13, weight: .semibold))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    VerdictPill(verdict: review.reviewState)
                    Spacer(minLength: 4)
                    Text(relativeTime(review.createdAt))
                        .font(typography.sans(11))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                }
                if !review.body.isEmpty {
                    Text(review.body)
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(2)
                }
                if mentionInChat != nil {
                    addToChatButton {
                        mentionInChat?(excerptForReview(review, prNumber: prNumber))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func commentRow(_ comment: PullRequestTimelineComment, prNumber: Int, indented: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if indented {
                Rectangle()
                    .fill(ClaudePalette.divider)
                    .frame(width: 2)
                    .padding(.vertical, 2)
            } else {
                AuthorAvatar(author: comment.author)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.author)
                        .font(typography.sans(13, weight: .semibold))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(relativeTime(comment.createdAt))
                        .font(typography.sans(11))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                }
                Text(comment.body)
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .lineLimit(2)
                if let location = comment.location {
                    Text("\((location.path as NSString).lastPathComponent):\(PaseoFormat.integer(location.line ?? 0))")
                        .font(typography.mono(11))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                        .lineLimit(1)
                }
                if mentionInChat != nil {
                    addToChatButton {
                        mentionInChat?(excerptForComment(comment, prNumber: prNumber))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func addToChatButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "at")
                    .font(.system(size: 11, weight: .medium))
                Text("Add to chat")
                    .font(typography.sans(11, weight: .medium))
            }
            .foregroundStyle(ClaudePalette.secondaryInk)
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to chat")
    }

    private func excerptForCheck(_ check: CheckoutPrCheck, prNumber: Int) -> String {
        var line = "PR #\(prNumber) — \(check.name) (\(check.status))"
        if let workflow = check.workflow, !workflow.isEmpty { line += " (\(workflow))" }
        if let url = check.url, !url.isEmpty { line += "\n\(url)" }
        return line
    }

    private func excerptForReview(_ review: PullRequestTimelineReview, prNumber: Int) -> String {
        var line = "PR #\(prNumber) — \(review.author) (\(verdictWord(review.reviewState)))"
        let quote = singleLineExcerpt(review.body)
        if !quote.isEmpty { line += ": \"\(quote)\"" }
        if !review.url.isEmpty { line += "\n\(review.url)" }
        return line
    }

    private func excerptForComment(_ comment: PullRequestTimelineComment, prNumber: Int) -> String {
        var line = "PR #\(prNumber) — \(comment.author)"
        if let location = comment.location {
            line += " on \((location.path as NSString).lastPathComponent):\(location.line ?? 0)"
        }
        let quote = singleLineExcerpt(comment.body)
        if !quote.isEmpty { line += ": \"\(quote)\"" }
        if !comment.url.isEmpty { line += "\n\(comment.url)" }
        return line
    }

    private func singleLineExcerpt(_ body: String, limit: Int = 160) -> String {
        let single = body
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return single.count > limit ? String(single.prefix(limit)) + "…" : single
    }

    private func verdictWord(_ verdict: PullRequestReviewVerdict) -> String {
        switch verdict {
        case .approved: "approved"
        case .changesRequested: "changes requested"
        case .commented: "commented"
        case .unknown(let raw): raw
        }
    }

    private func relativeTime(_ timestamp: Double) -> String {
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Small pieces

private struct AuthorAvatar: View {
    let author: String

    var body: some View {
        Text(String(author.prefix(1)).uppercased())
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ClaudePalette.secondaryInk)
            .frame(width: 28, height: 28)
            .background(ClaudePalette.chip, in: .circle)
            .accessibilityHidden(true)
    }
}

private struct VerdictPill: View {
    let verdict: PullRequestReviewVerdict

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: .capsule)
    }

    private var label: String {
        switch verdict {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .commented: "Commented"
        case .unknown(let raw): raw.capitalized
        }
    }

    private var tint: Color {
        switch verdict {
        case .approved: ClaudePalette.successInk
        case .changesRequested: ClaudePalette.failureInk
        case .commented: ClaudePalette.secondaryInk
        case .unknown: ClaudePalette.secondaryInk
        }
    }
}

private struct StatePill: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: .capsule)
    }
}

#endif
