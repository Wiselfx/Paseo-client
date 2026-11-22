#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// "Open on GitHub" (or the PR's forge), with the repository on the trailing side.
struct PROpenOnForgeRow: View {
    let status: CheckoutPrStatus

    @Environment(\.openURL) private var openURL

    var body: some View {
        let forge = Self.forgeName(status.forge)
        Button {
            if let url = URL(string: status.url) { openURL(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right.square")
                    .font(.glyph(.regular, weight: .regular))
                    .foregroundStyle(Palette.secondaryInk)
                Text("Open on \(forge)")
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                if let repoOwner = status.repoOwner, let repoName = status.repoName {
                    Text("\(repoOwner)/\(repoName)")
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open on \(forge)")
    }

    /// `.capitalized` turns "github" into "Github"; brand names keep their casing.
    private static func forgeName(_ raw: String?) -> String {
        switch (raw ?? "github").lowercased() {
        case "github": "GitHub"
        case "gitlab": "GitLab"
        default: (raw ?? "github").capitalized
        }
    }
}
#endif
