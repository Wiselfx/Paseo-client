#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One commit ahead of base: subject, short sha and age.
struct ChangesCommitRow: View {
    let commit: CheckoutCommit
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.subject)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(commit.shortSha)
                            .font(.paseo(.codeCaption))
                            .foregroundStyle(Palette.secondaryInk)
                        Text("· \(age)")
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Commit \(commit.shortSha), \(commit.subject)")
    }

    private var age: String {
        guard let date = PaseoDate.parse(commit.authorDate) else { return "" }
        return PaseoFormat.relative(date)
    }
}
#endif
