#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The header's PR badge: number and state, with a checks dot while open. Opens the PR.
struct ChangesPRChip: View {
    let badge: PullRequestBadge

    @Environment(\.openURL) private var openURL

    var body: some View {
        let tint = self.tint
        Button {
            if let url = URL(string: badge.url), !badge.url.isEmpty {
                openURL(url)
            }
        } label: {
            HStack(spacing: 5) {
                if badge.isOpen {
                    Circle().fill(checksTint).frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.paseo(.caption, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, Space.xs)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: .capsule)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pull request \(label)")
    }

    private var tint: Color {
        if badge.isDraft, badge.isOpen { return Palette.secondaryInk }
        if badge.isMerged { return Palette.unread }
        if badge.isOpen { return Palette.successInk }
        return Palette.tertiaryInk
    }

    private var checksTint: Color {
        switch badge.checks {
        case .passing: Palette.successInk
        case .failing: Palette.failureInk
        case .pending: Palette.warning
        case .none, .unknown: Palette.secondaryInk
        }
    }

    private var label: String {
        let number = badge.number.map { "#\($0)" } ?? "PR"
        if badge.isDraft, badge.isOpen { return "\(number) · Draft" }
        if badge.isMerged { return "\(number) · Merged" }
        if badge.isOpen { return number }
        return "\(number) · Closed"
    }
}
#endif
