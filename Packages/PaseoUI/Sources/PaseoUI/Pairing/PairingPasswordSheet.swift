#if canImport(UIKit)
import AVFoundation
import PaseoStore
import SwiftUI
import UIKit
import VisionKit

// MARK: - Password

/// "Password for {host}" — shown only after the daemon rejected the (encrypted) hello for
/// password reasons (doc 11 §8.3). Never stored in plain settings: the Keychain on success.
public struct PairingPasswordSheet: View {
    public let host: String
    public var error: String?
    /// True while a connect attempt is in flight (S1).
    public var isAttempting: Bool
    public var onConnect: (String) -> Void

    public init(
        host: String, error: String? = nil, isAttempting: Bool = false,
        onConnect: @escaping (String) -> Void
    ) {
        self.host = host
        self.error = error
        self.isAttempting = isAttempting
        self.onConnect = onConnect
    }
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""

    public var body: some View {
        SheetScaffold("Password for \(host)", detents: .large) {
            VStack(alignment: .leading, spacing: 12) {
                SecureField("Host password", text: $password)
                    .font(.paseo(.body))
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .background(Palette.chip, in: .rect(cornerRadius: Radius.md))
                    .accessibilityIdentifier("pairing.password.field")
                if let error {
                    Text(error)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                }
                Button {
                    submit()
                } label: {
                    if isAttempting {
                        ProgressView().controlSize(.small).tint(Palette.background)
                    } else {
                        Text("Connect")
                            .font(.paseo(.callout, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.ink)
                .disabled(password.isEmpty || isAttempting)
                .opacity(password.isEmpty || isAttempting ? 0.4 : 1)
                .accessibilityIdentifier("pairing.password.connect")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func submit() {
        guard !password.isEmpty, !isAttempting else { return }
        onConnect(password)
    }
}
#endif
