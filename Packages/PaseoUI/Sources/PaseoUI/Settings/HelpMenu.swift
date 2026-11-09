#if canImport(UIKit)
import SwiftUI

/// The upstream Help & support menu, adapted for iOS (hardware-keyboard shortcuts omitted).
/// **Not wired in this build**: the Settings navigator and the sidebar footer are outside this
/// ticket's file list, and the correct host for this menu is one of those two. The full menu is
/// staged here, reviewed and ready — wiring it is a few lines (a Settings row opening it, or the
/// sidebar footer menu the app keeps its actions in). `onRunDiagnostics` is `nil` while the
/// diagnostics page is unreachable, and the item hides.
struct HelpMenuItems: View {
    /// Presents the app's Diagnostics page (M4e). Nil hides the item.
    var onRunDiagnostics: (() -> Void)?
    /// The connected host's daemon version, for the footer line (nil pre-connect).
    var daemonVersion: String?

    @Environment(\.openURL) private var openURL
    private let typography = ClaudeTypography()

    private static let changelogURL = "https://raw.githubusercontent.com/getpaseo/paseo/main/CHANGELOG.md"
    private static let githubIssueURL = "https://github.com/getpaseo/paseo/issues/new"
    private static let githubRepoURL = "https://github.com/getpaseo/paseo"
    private static let sponsorURL = "https://github.com/sponsors/boudra"
    private static let discordURL = "https://discord.gg/jz8T2uahpH"

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short.map { "Paseo \($0)" } ?? "Paseo"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            label("Help")
            if let onRunDiagnostics {
                menuRow("Run diagnostics", systemImage: "stethoscope", action: onRunDiagnostics)
                    .accessibilityIdentifier("help.diagnostics")
            }
            linkRow("What's new", systemImage: "gift", url: Self.changelogURL)
                .accessibilityIdentifier("help.whatsNew")

            Divider().padding(.horizontal, 6).padding(.vertical, 2)

            label("Report an issue")
            linkRow("Discord", systemImage: "bubble.left.and.bubble.right", url: Self.discordURL)
                .accessibilityIdentifier("help.discord")
            linkRow("Create GitHub issue", systemImage: "ladybug", url: Self.githubIssueURL)
                .accessibilityIdentifier("help.github")

            Divider().padding(.horizontal, 6).padding(.vertical, 2)

            label("Community")
            linkRow("Star on GitHub", systemImage: "star", url: Self.githubRepoURL)
                .accessibilityIdentifier("help.star")
            linkRow("Sponsor", systemImage: "heart", url: Self.sponsorURL)
                .accessibilityIdentifier("help.sponsor")

            Text(appVersion + (daemonVersion.map { " · Daemon \($0)" } ?? ""))
                .font(.system(size: 11))
                .foregroundStyle(ClaudePalette.captionInk)
                .padding(.horizontal, 8)
                .padding(.top, 6)
        }
        .padding(.vertical, 6)
    }

    // MARK: Pieces

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(ClaudePalette.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
    }

    private func menuRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(typography.sans(15))
                .foregroundStyle(ClaudePalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func linkRow(_ title: String, systemImage: String, url: String) -> some View {
        menuRow(title, systemImage: systemImage) {
            Haptics.selection()
            if let target = URL(string: url) { openURL(target) }
        }
    }
}
#endif
