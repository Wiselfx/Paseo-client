#if canImport(UIKit)
import SwiftUI

/// Where is your daemon, and what's its password. The app does the connecting; this view only
/// collects the details and shows the outcome. ClaudeUI's sheet chrome, Paseo's fields.
public struct ConnectView: View {
    public enum Status: Equatable {
        case idle
        case connecting
        case failed(String)
    }

    @Binding var host: String
    @Binding var port: String
    @Binding var password: String
    var status: Status
    var onConnect: () -> Void

    private let typography = ClaudeTypography()

    public init(
        host: Binding<String>, port: Binding<String>, password: Binding<String>, status: Status,
        onConnect: @escaping () -> Void
    ) {
        _host = host
        _port = port
        _password = password
        self.status = status
        self.onConnect = onConnect
        ClaudeFontResources.register()
    }

    private var connecting: Bool { status == .connecting }

    private var canConnect: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !connecting
    }

    public var body: some View {
        ZStack {
            ClaudePalette.background.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer(minLength: 20)
                VStack(spacing: 6) {
                    Text("Paseo").font(typography.serif(34, relativeTo: .largeTitle))
                    Text("Connect to your daemon")
                        .font(typography.sans(15))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                }
                VStack(spacing: 12) {
                    RowGroup {
                        field(
                            "Host", text: $host, prompt: "192.168.1.20 or my-box",
                            symbol: "desktopcomputer", keyboard: .URL,
                            contentType: .URL
                        )
                        RowDivider()
                        field("Port", text: $port, prompt: "6767", symbol: "number", keyboard: .numberPad)
                        RowDivider()
                        secureField("Password", text: $password, prompt: "Daemon password")
                    }
                    connectButton
                    if case .failed(let message) = status {
                        Text(message)
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                Spacer()
                Text(
                    "Use your machine's LAN or Tailscale address. Set a password with `paseo daemon set-password`."
                )
                .font(typography.sans(12))
                .foregroundStyle(ClaudePalette.captionInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
            }
        }
        .foregroundStyle(ClaudePalette.ink)
        .tint(ClaudePalette.ink)
        .sensoryFeedback(.error, trigger: status) { _, new in
            if case .failed = new { true } else { false }
        }
    }

    private var connectButton: some View {
        Button(action: onConnect) {
            HStack(spacing: 8) {
                Text(connecting ? "Connecting…" : "Connect")
                    .font(typography.sans(16, weight: .medium))
                if connecting { ProgressView().controlSize(.small).tint(ClaudePalette.background) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(ClaudePalette.background)
            .background(ClaudePalette.ink, in: .capsule)
            .opacity(canConnect ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canConnect)
        .accessibilityIdentifier("connect.submit")
    }

    private func field(
        _ title: String, text: Binding<String>, prompt: String, symbol: String,
        keyboard: UIKeyboardType = .default, contentType: UITextContentType? = nil
    ) -> some View {
        HStack(spacing: 12) {
            fieldSymbol(symbol)
            VStack(alignment: .leading, spacing: 2) {
                fieldTitle(title)
                TextField(
                    "", text: text,
                    prompt: Text(prompt).foregroundStyle(ClaudePalette.captionInk)
                )
                .font(typography.sans(17))
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func secureField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 12) {
            fieldSymbol("lock")
            VStack(alignment: .leading, spacing: 2) {
                fieldTitle(title)
                SecureField(
                    "", text: text,
                    prompt: Text(prompt).foregroundStyle(ClaudePalette.captionInk)
                )
                .font(typography.sans(17))
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit(onConnect)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func fieldSymbol(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .light))
            .foregroundStyle(ClaudePalette.tertiaryInk)
            .frame(width: 23)
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(typography.sans(12)).foregroundStyle(ClaudePalette.secondaryInk)
    }
}
#endif
