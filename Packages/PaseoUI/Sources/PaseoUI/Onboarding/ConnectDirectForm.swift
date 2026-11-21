#if canImport(UIKit)
import SwiftUI

/// The direct-connection form: host, port, password, TLS and the Advanced URI. `ConnectView` owns
/// the values and the validation; this view lays them out.
struct ConnectDirectForm: View {
    @Binding var host: String
    @Binding var port: String
    @Binding var password: String
    @Binding var useTLS: Bool
    @Binding var connectionURI: String
    /// Owned by `ConnectView` so the disclosure survives a trip to the saved hosts and back.
    @Binding var showAdvanced: Bool
    /// True when saved hosts exist, so the form offers a way back to them.
    let showsBackButton: Bool
    let portError: String?
    let hostError: String?
    let uriError: String?
    let canConnect: Bool
    let onBack: () -> Void
    let onConnect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            if showsBackButton {
                HStack {
                    Button(action: onBack) {
                        Label("Saved hosts", systemImage: "chevron.left")
                            .font(.paseo(.callout, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("connect.backToHosts")
                    Spacer()
                }
            }
            RowGroup {
                ConnectFormField(
                    title: "Host", text: $host, prompt: "example.com or 192.0.2.10",
                    symbol: "desktopcomputer", keyboard: .URL, contentType: .URL,
                    identifier: "connect.host")
                RowDivider()
                ConnectFormField(
                    title: "Port", text: $port, prompt: "6767", symbol: "number",
                    keyboard: .numberPad, identifier: "connect.port")
                if let portError {
                    ConnectErrorCaption(message: portError)
                }
                if let hostError {
                    ConnectErrorCaption(message: hostError)
                }
                RowDivider()
                ConnectSecureField(
                    title: "Password", text: $password, prompt: "Host password",
                    identifier: "connect.password", canConnect: canConnect,
                    onConnect: onConnect)
                RowDivider()
                Toggle(isOn: $useTLS) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use TLS (wss)")
                            .font(.paseo(.body))
                        Text("For hosts behind a TLS terminator (Caddy, nginx).")
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                .tint(Palette.toggleTint)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityIdentifier("connect.tls")
                RowDivider()
                Button(action: toggleAdvanced) {
                    HStack(spacing: 12) {
                        ConnectFieldSymbol(symbol: "chevron.down.chevron.up")
                        Text("Advanced")
                            .font(.paseo(.body))
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.glyph(.small, weight: .semibold))
                            .foregroundStyle(Palette.secondaryInk)
                            .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("connect.advanced")
                .paseoFeedback(.selection, trigger: showAdvanced)
                if showAdvanced {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 2) {
                        TextField(
                            "Connection URI", text: $connectionURI,
                            prompt: Text("wss://host:6767/ws").foregroundStyle(Palette.captionInk)
                        )
                        .font(.paseo(.code))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("connect.uri")
                        Text(uriError ?? "Overrides host, port and the TLS switch while filled.")
                            .font(.paseo(.caption))
                            .foregroundStyle(uriError == nil ? Palette.secondaryInk : Palette.failureInk)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// Reduce Motion drops the disclosure animation, not the disclosure.
    private func toggleAdvanced() {
        withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) { showAdvanced.toggle() }
    }
}
#endif
