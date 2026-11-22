#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The PR's activity: reviews with their replies, then the comments that belong to no listed
/// review, with a refresh control and the timeline's loading and error states.
struct PRActivityBlock: View {
    let status: CheckoutPrStatus
    let timeline: PullRequestTimelineStore

    var body: some View {
        // Group once per evaluation: each review's replies, and the comments that belong to no
        // listed review.
        let reviews = timeline.items.compactMap { item -> PullRequestTimelineReview? in
            if case .review(let review) = item { review } else { nil }
        }
        let comments = timeline.items.compactMap { item -> PullRequestTimelineComment? in
            if case .comment(let comment) = item { comment } else { nil }
        }
        let reviewIds = Set(reviews.map(\.id))
        let repliesByReview = Dictionary(
            grouping: comments.filter { $0.reviewId != nil }, by: { $0.reviewId ?? "" })
        let standaloneComments = comments.filter { comment in
            guard let reviewId = comment.reviewId else { return true }
            return !reviewIds.contains(reviewId)
        }
        let prNumber = status.number ?? 0
        VStack(alignment: .leading, spacing: 0) {
            header
            if let error = timeline.error {
                PRTimelineErrorRow(error: error) {
                    Task { await load() }
                }
            } else if reviews.isEmpty && standaloneComments.isEmpty && unknownItems.isEmpty {
                if !timeline.isLoading {
                    Text("No reviews yet.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.horizontal, Space.lg)
                        .padding(.bottom, 10)
                }
            } else {
                ForEach(reviews) { review in
                    PRReviewRow(review: review, prNumber: prNumber)
                    ForEach(repliesByReview[review.id] ?? []) { comment in
                        PRCommentRow(comment: comment, prNumber: prNumber, indented: true)
                    }
                }
                ForEach(standaloneComments) { comment in
                    PRCommentRow(comment: comment, prNumber: prNumber, indented: false)
                }
                ForEach(unknownItems, id: \.self) { kind in
                    Text("Unsupported item · \(kind)")
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.captionInk)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.xs)
                }
                if timeline.truncated {
                    Text("Only some items are shown.")
                        .font(.paseo(.caption2))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.xs)
                }
            }
        }
        .padding(.bottom, 10)
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            Text("Activity")
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: 8)
            if timeline.isLoading {
                ProgressView().controlSize(.mini)
            } else {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.glyph(.small, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(width: 28, height: 28)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh timeline")
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.xs)
        .padding(.bottom, 6)
    }

    /// Timeline kinds this client can't draw. A debugging aid: release builds list none.
    private var unknownItems: [String] {
        #if DEBUG
        timeline.items.compactMap { item -> String? in
            if case .unknown(let kind) = item { kind } else { nil }
        }
        #else
        []
        #endif
    }

    private func load() async {
        await timeline.load(
            prNumber: status.number ?? 0, repoOwner: status.repoOwner, repoName: status.repoName)
    }
}
#endif
