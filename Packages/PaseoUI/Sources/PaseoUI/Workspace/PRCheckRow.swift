#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One check: its outcome glyph, name, workflow and duration. Opens the check's page when it has
/// one; the context menu adds it to the chat.
struct PRCheckRow: View {
    let check: CheckoutPrCheck
    let prNumber: Int

    @Environment(\.openURL) private var openURL
    @Environment(\.mentionInChat) private var mentionInChat

    var body: some View {
        let failing = PRCheckStatus.isFailing(check.status)
        let passing = PRCheckStatus.isPassing(check.status)
        Button {
            if let url = check.url, let target = URL(string: url) {
                openURL(target)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: passing ? "checkmark.circle.fill" : failing ? "xmark.circle.fill" : "circle.dashed")
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(passing ? Palette.successInk : failing ? Palette.failureInk : Palette.warning)
                VStack(alignment: .leading, spacing: 1) {
                    Text(check.name)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let workflow = check.workflow, !workflow.isEmpty {
                        Text(workflow)
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.tertiaryInk)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let duration = check.duration, !duration.isEmpty {
                    Text(duration)
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(check.url == nil || check.url?.isEmpty == true)
        .accessibilityLabel("Check \(check.name), \(check.status)")
        .contextMenu {
            if let mentionInChat {
                Button("Add to chat") {
                    mentionInChat(PRTimelineText.excerpt(check: check, prNumber: prNumber))
                }
            }
        }
    }
}
#endif
