#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → About: the app and its version, this host's identity, and the two source links.
struct AboutPage: View {
    let session: HostSession

    @Environment(\.openURL) private var openURL

    var body: some View {
        PageList {
            Section {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Paseo Client")
                        .font(.paseo(.largeTitle))
                        .foregroundStyle(Palette.ink)
                    Text(versionLine)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                    Text("A native client for the Paseo host.")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.md)
                .panelRow()
            }
            Section {
                ListRow(
                    title: "Host",
                    accessory: ListRow.Accessory.value(session.serverInfo?.hostname ?? "Not connected")
                )
                .panelRow()
                ListRow(
                    title: "Host version",
                    accessory: ListRow.Accessory.value(session.serverInfo?.version ?? "Unknown")
                )
                .panelRow()
            } header: {
                Text("This host")
            }
            Section {
                linkRow(
                    "Paseo host", detail: "github.com/getpaseo/paseo",
                    url: URL(string: "https://github.com/getpaseo/paseo"))
                linkRow(
                    "Paseo Client", detail: "github.com/Wiselfx/Paseo-client",
                    url: URL(string: "https://github.com/Wiselfx/Paseo-client"))
            } header: {
                Text("Links")
            }
        }
        .inlinePageTitle("About")
    }

    private func linkRow(_ title: String, detail: String, url: URL?) -> some View {
        ListRow(
            title: title,
            subtitle: detail,
            accessory: ListRow.Accessory.chevron,
            action: {
                guard let url else { return }
                Haptics.selection()
                openURL(url)
            }
        )
        .panelRow()
        .accessibilityLabel("\(title), opens in browser")
    }

    private var versionLine: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        default: return "Unknown"
        }
    }
}
#endif
