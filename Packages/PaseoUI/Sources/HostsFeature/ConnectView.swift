import DesignSystem
import SwiftUI

/// Where is your daemon, and what's its password. The app does the connecting; this view only
/// collects the details and shows the outcome.
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

    public init(host: Binding<String>, port: Binding<String>, password: Binding<String>, status: Status, onConnect: @escaping () -> Void) {
        _host = host
        _port = port
        _password = password
        self.status = status
        self.onConnect = onConnect
    }

    public var body: some View {
        Form {
            Section {
                TextField("Host (e.g. 192.168.1.20 or my-box)", text: $host)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
                SecureField("Daemon password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Paseo daemon")
            } footer: {
                Text("Use your machine's LAN or Tailscale address. Set a password with `paseo daemon set-password`.")
            }

            Section {
                Button(action: onConnect) {
                    HStack {
                        Text(status == .connecting ? "Connecting…" : "Connect")
                        Spacer()
                        if status == .connecting { ProgressView() }
                    }
                }
                .disabled(host.isEmpty || status == .connecting)
            } footer: {
                if case .failed(let message) = status {
                    Text(message).foregroundStyle(Palette.failure)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Connect")
        .sensoryFeedback(.error, trigger: status) { _, new in
            if case .failed = new { true } else { false }
        }
    }
}
