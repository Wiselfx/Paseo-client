#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One comment in the PR activity. A reply under its review is indented behind a rule instead of
/// carrying its own avatar.
struct PRCommentRow: View {
    let comment: PullRequestTimelineComment
    let prNumber: Int
    let indented: Bool

    @Environment(\.mentionInChat) private var mentionInChat

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            if indented {
                Rectangle()
                    .fill(Palette.divider)
                    .frame(width: 2)
                    .padding(.vertical, 2)
            } else {
                AuthorAvatar(author: comment.author)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.author)
                        .font(.paseo(.footnote, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(PRTimelineText.relativeTime(comment.createdAt))
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                Text(comment.body)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
                if let location = comment.location {
                    Text("\((location.path as NSString).lastPathComponent):\(PaseoFormat.integer(location.line ?? 0))")
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                }
                if let mentionInChat {
                    PRAddToChatButton {
                        mentionInChat(PRTimelineText.excerpt(comment: comment, prNumber: prNumber))
                    }
                }
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
    }
}
#endif
