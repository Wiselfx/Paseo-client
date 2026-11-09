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

    private let typography = ClaudeTypography()

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
                            Haptics.selection()
                            stage = .welcome
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Welcome")
                            }
                            .font(typography.sans(16, weight: .medium))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .frame(height: 44)
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
        .background(ClaudePalette.background.ignoresSafeArea())
        .foregroundStyle(ClaudePalette.ink)
        .sheet(isPresented: $showAppearance) { WelcomeAppearanceSheet() }
    }

    // MARK: Welcome

    private var welcomeContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)
                Text("Paseo")
                    .font(typography.serif(56, relativeTo: .largeTitle))
                VStack(spacing: 8) {
                    Text("Welcome to Paseo")
                        .font(typography.serif(24))
                    Text("Connect your computer to get started")
                        .font(typography.sans(15))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    Button {
                        Haptics.selection()
                        if let url = URL(string: "https://paseo.sh") { openURL(url) }
                    } label: {
                        HStack(spacing: 4) {
                            Text("paseo.sh")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(typography.sans(14, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink.opacity(0.75))
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
                    Haptics.selection()
                    showAppearance = true
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                        .font(typography.sans(15, weight: .medium))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("welcome.settings")
                Spacer()
                Text(versionLine)
                    .font(typography.mono(11, relativeTo: .footnote))
                    .foregroundStyle(ClaudePalette.captionInk)
                    .padding(.bottom, 14)
            }
            .padding(.horizontal, 32)
        }
        .scrollIndicators(.hidden)
    }

    private var directTile: some View {
        Button {
            Haptics.selection()
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
            Haptics.selection()
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
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(ClaudePalette.background)
                .frame(width: 34, height: 34)
                .background(ClaudePalette.ink, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(typography.sans(17, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                Text(description)
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.secondaryInk)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 15))
                .foregroundStyle(ClaudePalette.secondaryInk)
        }
        .padding(.horizontal, 18)
        .frame(height: 68)
        .background(ClaudePalette.panel, in: .rect(cornerRadius: 20))
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
    @AppStorage(PaseoSettingsKeys.appearance) private var appearance = ClaudeAppearance.system.rawValue
    @AppStorage(ClaudeTextScale.contentStorageKey) private var contentTextSize = ClaudeTextScale.Content.medium.rawValue
    @AppStorage(ClaudeTextScale.codeStorageKey) private var codeFontSize = ClaudeTextScale.Code.medium.rawValue

    @Environment(\.dismiss) private var dismiss
    private let typography = ClaudeTypography()

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Appearance", close: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        ForEach([ClaudeAppearance.light, .dark, .pureBlack, .system], id: \.self) { choice in
                            Button {
                                Haptics.selection()
                                appearance = choice.rawValue
                            } label: {
                                VStack(spacing: 8) {
                                    tilePreview(choice)
                                        .frame(height: 64)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 14).stroke(
                                                appearance == choice.rawValue ? Color.blue : .clear,
                                                lineWidth: 2)
                                        }
                                    Text(choice.rawValue)
                                        .font(.system(size: 12))
                                        .foregroundStyle(
                                            appearance == choice.rawValue
                                                ? .blue : ClaudePalette.secondaryInk)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(choice.rawValue) appearance")
                            .accessibilityAddTraits(
                                appearance == choice.rawValue ? .isSelected : [])
                            .accessibilityIdentifier("welcome.appearance.\(choice.rawValue)")
                        }
                    }
                    scaleRow("Content size", options: ClaudeTextScale.Content.allCases,
                             current: contentTextSize) { contentTextSize = $0.rawValue }
                    scaleRow("Code size", options: ClaudeTextScale.Code.allCases,
                             current: codeFontSize) { codeFontSize = $0.rawValue }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
    }

    private func tilePreview(_ choice: ClaudeAppearance) -> some View {
        switch choice {
        case .light:
            ZStack { Color(white: 0.97); bars(dark: true) }
        case .dark:
            ZStack { Color(white: 0.08); bars(dark: false) }
        case .pureBlack:
            ZStack { Color(white: 0); bars(dark: false) }
        case .system:
            ZStack {
                HStack(spacing: 0) { Color(white: 0.97); Color(white: 0.08) }
                bars(dark: true)
            }
        }
    }

    private func bars(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule()
                .fill((dark ? Color.black : Color.white).opacity(dark ? 0.8 : 0.5))
                .frame(width: 44, height: 5)
            Capsule()
                .fill((dark ? Color.black : Color.white).opacity(dark ? 0.4 : 0.3))
                .frame(width: 28, height: 5)
            Spacer(minLength: 0)
        }
        .padding(12)
        .clipShape(.rect(cornerRadius: 14))
    }

    private func scaleRow<Option: CaseIterable & RawRepresentable & Equatable>(
        _ title: String, options: [Option], current: String,
        onSelect: @escaping (Option) -> Void
    ) -> some View where Option.RawValue == String {
        HStack {
            Text(title)
                .font(.system(size: 17))
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
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(ClaudePalette.panel, in: .rect(cornerRadius: 16))
    }
}
#endif
