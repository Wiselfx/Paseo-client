#if canImport(UIKit)
import SwiftUI

/// The welcome page proper: the mark, one line, the connection method tiles and the
/// Appearance entry. `WelcomeView` owns which stage is showing and passes the actions in.
struct WelcomeHome: View {
    /// Scan QR / Paste pairing link tiles (R18); nil hides the tile (previews).
    var onScan: (() -> Void)?
    var onPaste: (() -> Void)?
    let onDirect: () -> Void
    let onAppearance: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)
                // Upstream's welcome screen leads with the butterfly at 96 pt
                // (`packages/app/src/components/welcome-screen.tsx:266`).
                PaseoLogo(size: 96)
                VStack(spacing: 8) {
                    Text("Welcome to Paseo")
                        .font(.paseo(.largeTitle))
                    Text("Connect your computer to get started")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                    if let site = URL(string: "https://paseo.sh") {
                        Link(destination: site) {
                            HStack(spacing: 4) {
                                Text("paseo.sh")
                                Image(systemName: "arrow.up.right")
                                    .font(.glyph(.small, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            .font(.paseo(.callout, weight: .medium))
                            // A `Link` tints with the accent otherwise.
                            .foregroundStyle(Palette.ink.opacity(0.75))
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .accessibilityIdentifier("welcome.site")
                    }
                }
                VStack(spacing: 10) {
                    if let onScan {
                        ConnectionMethodTile(
                            title: "Scan QR code", description: "Encrypted relay connection.",
                            symbol: "qrcode.viewfinder", action: onScan)
                            .accessibilityIdentifier("welcome.scan")
                    }
                    ConnectionMethodTile(
                        title: "Direct connection", description: "Local network or VPN.",
                        symbol: "link", action: onDirect)
                        .accessibilityIdentifier("welcome.direct")
                    if let onPaste {
                        ConnectionMethodTile(
                            title: "Paste pairing link", description: "Encrypted relay connection.",
                            symbol: "clipboard", action: onPaste)
                            .accessibilityIdentifier("welcome.paste")
                    }
                }
                .padding(.top, 10)
                Button(action: onAppearance) {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("welcome.settings")
                Spacer()
                Text(versionLine)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.captionInk)
                    .padding(.bottom, 14)
            }
            .padding(.horizontal, 32)
        }
        .scrollIndicators(.hidden)
    }

    private var versionLine: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?): return "Paseo Client \(short) (\(build))"
        case let (short?, nil): return "Paseo Client \(short)"
        default: return "Paseo Client"
        }
    }
}
#endif
