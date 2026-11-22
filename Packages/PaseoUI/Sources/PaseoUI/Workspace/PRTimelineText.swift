#if canImport(UIKit)
import Foundation
import PaseoStore

/// The PR pane's words: the excerpts "Add to chat" inserts, verdict wording and relative times.
@MainActor
enum PRTimelineText {
    static func excerpt(check: CheckoutPrCheck, prNumber: Int) -> String {
        var line = "PR #\(prNumber) — \(check.name) (\(check.status))"
        if let workflow = check.workflow, !workflow.isEmpty { line += " (\(workflow))" }
        if let url = check.url, !url.isEmpty { line += "\n\(url)" }
        return line
    }

    static func excerpt(review: PullRequestTimelineReview, prNumber: Int) -> String {
        var line = "PR #\(prNumber) — \(review.author) (\(verdictWord(review.reviewState)))"
        let quote = singleLine(review.body)
        if !quote.isEmpty { line += ": \"\(quote)\"" }
        if !review.url.isEmpty { line += "\n\(review.url)" }
        return line
    }

    static func excerpt(comment: PullRequestTimelineComment, prNumber: Int) -> String {
        var line = "PR #\(prNumber) — \(comment.author)"
        if let location = comment.location {
            line += " on \((location.path as NSString).lastPathComponent):\(location.line ?? 0)"
        }
        let quote = singleLine(comment.body)
        if !quote.isEmpty { line += ": \"\(quote)\"" }
        if !comment.url.isEmpty { line += "\n\(comment.url)" }
        return line
    }

    static func verdictLabel(_ verdict: PullRequestReviewVerdict) -> String {
        switch verdict {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .commented: "Commented"
        case .unknown(let raw): raw.capitalized
        }
    }

    /// The daemon sends seconds or milliseconds; anything past 10^10 is milliseconds.
    static func relativeTime(_ timestamp: Double) -> String {
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
        return PaseoFormat.relative(Date(timeIntervalSince1970: seconds))
    }

    private static func verdictWord(_ verdict: PullRequestReviewVerdict) -> String {
        switch verdict {
        case .approved: "approved"
        case .changesRequested: "changes requested"
        case .commented: "commented"
        case .unknown(let raw): raw
        }
    }

    private static func singleLine(_ body: String, limit: Int = 160) -> String {
        let single = body
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return single.count > limit ? String(single.prefix(limit)) + "…" : single
    }
}
#endif
