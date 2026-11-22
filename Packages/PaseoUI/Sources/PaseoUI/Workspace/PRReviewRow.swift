#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One review in the PR activity: author, verdict pill, time, the start of its body.
struct PRReviewRow: View {
    let review: PullRequestTimelineReview
    let prNumber: Int

    @Environment(\.mentionInChat) private var mentionInChat

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            AuthorAvatar(author: review.author)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(review.author)
                        .font(.paseo(.footnote, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    StatePill(PRTimelineText.verdictLabel(review.reviewState), tone: verdictTone)
                    Spacer(minLength: 4)
                    Text(PRTimelineText.relativeTime(review.createdAt))
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                if !review.body.isEmpty {
                    Text(review.body)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                }
                if let mentionInChat {
                    PRAddToChatButton {
                        mentionInChat(PRTimelineText.excerpt(review: review, prNumber: prNumber))
                    }
                }
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
    }

    private var verdictTone: StatePill.Tone {
        switch review.reviewState {
        case .approved: .success
        case .changesRequested: .failure
        case .commented, .unknown: .neutral
        }
    }
}
#endif
