#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → About → Help & support: upstream's help menu (hardware-keyboard shortcuts omitted),
/// with Run diagnostics pushing the Diagnostics page (audit C #10: Help → Diagnostics nests).
struct HelpPage: View {
    let session: HostSession

    @Environment(\.openURL) private var openURL

    private static let changelogURL = "https://raw.githubusercontent.com/getpaseo/paseo/main/CHANGELOG.md"
    private static let githubIssueURL = "https://github.com/getpaseo/paseo/issues/new"
    private static let githubRepoURL = "https://github.com/getpaseo/paseo"
    private static let sponsorURL = "https://github.com/sponsors/boudra"
    private static let discordURL = "https://discord.gg/jz8T2uahpH"

    var body: some View {
        PageList {
            Section {
                NavigationLink(value: SettingsRoute.diagnostics) {
                    ListRow(title: "Run diagnostics", systemImage: "stethoscope")
                }
                .panelRow()
                .accessibilityIdentifier("help.diagnostics")
                linkRow("What's new", systemImage: "gift", url: Self.changelogURL)
                    .accessibilityIdentifier("help.whatsNew")
            } header: {
                Text("Help")
            }
            Section {
                linkRow("Discord", systemImage: "bubble.left.and.bubble.right", url: Self.discordURL)
                    .accessibilityIdentifier("help.discord")
                linkRow("Create GitHub issue", systemImage: "ladybug", url: Self.githubIssueURL)
                    .accessibilityIdentifier("help.github")
            } header: {
                Text("Report an issue")
            }
            Section {
                linkRow("Star on GitHub", systemImage: "star", url: Self.githubRepoURL)
                    .accessibilityIdentifier("help.star")
                linkRow("Sponsor", systemImage: "heart", url: Self.sponsorURL)
                    .accessibilityIdentifier("help.sponsor")
            } header: {
                Text("Community")
            } footer: {
                Text(appVersion + (session.serverInfo?.version.map { " · Host \($0)" } ?? ""))
            }
        }
        .inlinePageTitle("Help & support")
    }

    private func linkRow(_ title: String, systemImage: String, url: String) -> some View {
        ListRow(title: title, systemImage: systemImage, action: {
            Haptics.selection()
            if let target = URL(string: url) { openURL(target) }
        })
        .panelRow()
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short.map { "Paseo \($0)" } ?? "Paseo"
    }
}
#endif
