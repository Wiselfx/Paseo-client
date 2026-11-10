#if canImport(UIKit)
import SwiftUI

/// First run with no saved host (M1b): the Paseo mark, one line, and the connection methods.
/// Direct (host/port form) plus the relay methods — Scan QR / Paste pairing link (R18).
/// Remote SSH stays desktop-only. "Settings" opens a pre-connect appearance sheet; the full Settings
/// screen needs a host. Shown once, before the first successful connection; the flag flips in
/// `AppModel.performConnect`.
public struct WelcomeView<DirectForm: View>: View {
    /// The direct-connection form (M1b's `ConnectView`), revealed by the primary tile.
    let directForm: DirectForm
    /// Scan QR / Paste pairing link tiles (R18); nil hides the tiles (previews).
    var onScan: (() -> Void)?
    var onPaste: (() -> Void)?

    @Environment(\.openURL) private var openURL
    @State private var stage: Stage = .welcome
    @State private var showAppearance = false


    enum Stage { case welcome, directForm }

    public init(
        onScan: (() -> Void)? = nil, onPaste: (() -> Void)? = nil,
        @ViewBuilder directForm: () -> DirectForm
    ) {
        self.onScan = onScan
        self.onPaste = onPaste
        self.directForm = directForm()
    }

    public var body: some View {
        Group {
            switch stage {
            case .welcome: welcomeContent
            case .directForm:
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            stage = .welcome
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Welcome")
                            }
                            .font(.paseo(.callout, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("welcome.back")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    directForm
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
        .sheet(isPresented: $showAppearance) { WelcomeAppearanceSheet() }
    }

    // MARK: Welcome

    private var welcomeContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)
                Text("Paseo")
                    .font(.paseo(.hero))
                VStack(spacing: 8) {
                    Text("Welcome to Paseo")
                        .font(.paseo(.largeTitle))
                    Text("Connect your computer to get started")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                    Button {
                        if let url = URL(string: "https://paseo.sh") { openURL(url) }
                    } label: {
                        HStack(spacing: 4) {
                            Text("paseo.sh")
                            Image(systemName: "arrow.up.right")
                                .font(.glyph(.small, weight: .semibold))
                        }
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("welcome.site")
                }
                VStack(spacing: 10) {
                    if let onScan {
                        tile(
                            title: "Scan QR code", description: "Encrypted relay connection.",
                            symbol: "qrcode.viewfinder", id: "welcome.scan", action: onScan)
                    }
                    directTile
                    if let onPaste {
                        tile(
                            title: "Paste pairing link", description: "Encrypted relay connection.",
                            symbol: "clipboard", id: "welcome.paste", action: onPaste)
                    }
                }
                .padding(.top, 10)
                Button {
                    showAppearance = true
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(minHeight: 40)
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

    private var directTile: some View {
        Button {
            stage = .directForm
        } label: {
            tileContent(
                title: "Direct connection", description: "Local network or VPN.", symbol: "link")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("welcome.direct")
    }

    private func tile(
        title: String, description: String, symbol: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            tileContent(title: title, description: description, symbol: symbol)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func tileContent(title: String, description: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.glyph(.regular, weight: .light))
                .foregroundStyle(Palette.background)
                .frame(width: 34, height: 34)
                .background(Palette.ink, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.paseo(.body, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(description)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.glyph(.regular))
                .foregroundStyle(Palette.secondaryInk)
        }
        .padding(.horizontal, 18)
        .frame(height: 68)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
        .contentShape(.rect)
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

/// The pre-connect Settings entry: appearance and text sizes, using the same keys as the
/// general settings page. The full Settings screen needs a host (it is host-scoped).
private struct WelcomeAppearanceSheet: View {
    @AppStorage(ClaudeTextScale.contentStorageKey) private var contentTextSize = ClaudeTextScale.Content.medium.rawValue
    @AppStorage(ClaudeTextScale.codeStorageKey) private var codeFontSize = ClaudeTextScale.Code.medium.rawValue

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Appearance", close: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AppearancePicker(identifierPrefix: "welcome.appearance")
                    scaleRow("Content size", options: ClaudeTextScale.Content.allCases,
                             current: contentTextSize) { contentTextSize = $0.rawValue }
                    scaleRow("Code size", options: ClaudeTextScale.Code.allCases,
                             current: codeFontSize) { codeFontSize = $0.rawValue }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
    }


    private func scaleRow<Option: CaseIterable & RawRepresentable & Equatable>(
        _ title: String, options: [Option], current: String,
        onSelect: @escaping (Option) -> Void
    ) -> some View where Option.RawValue == String {
        HStack {
            Text(title)
                .font(.paseo(.body))
            Spacer(minLength: 8)
            Menu {
                ForEach(Array(options), id: \.rawValue) { option in
                    Button {
                        Haptics.selection()
                        onSelect(option)
                    } label: {
                        Label(
                            option.rawValue,
                            systemImage: current == option.rawValue ? "checkmark" : "circle")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(current)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
    }
}
#endif
