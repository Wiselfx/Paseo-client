#if canImport(UIKit)
import SwiftUI

/// R18 pairing UI: add-host methods, QR scan, paste, host confirmation, password prompt.
/// Wording is upstream's `en.ts` `pairing.*` verbatim (cited per string); the fingerprint
/// rule is upstream `runtime/host-confirmation.ts` (`HostConfirmation.keyFingerprint`).
/// The offer rides in the link fragment — the app never logs or stores it.

// MARK: - Add host methods

/// "Add connection" (upstream `pairing.connectionMethods.*`): Direct / Scan QR code /
/// Paste pairing link. Remote SSH is desktop-only (iOS has no SSH tunnel).
public struct AddHostMethodsSheet: View {
    public var onDirect: () -> Void
    public var onScan: () -> Void
    public var onPaste: () -> Void

    public init(onDirect: @escaping () -> Void, onScan: @escaping () -> Void, onPaste: @escaping () -> Void) {
        self.onDirect = onDirect
        self.onScan = onScan
        self.onPaste = onPaste
    }

    public var body: some View {
        SheetScaffold("Add connection", detents: .large) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ConnectionMethodTile(
                        title: "Direct connection", description: "Local network or VPN.",
                        symbol: "link", action: onDirect)
                        .accessibilityIdentifier("pairing.direct")
                    ConnectionMethodTile(
                        title: "Scan QR code", description: "Encrypted relay connection.",
                        symbol: "qrcode.viewfinder", action: onScan)
                        .accessibilityIdentifier("pairing.scan")
                    ConnectionMethodTile(
                        title: "Paste pairing link", description: "Encrypted relay connection.",
                        symbol: "clipboard", action: onPaste)
                        .accessibilityIdentifier("pairing.paste")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
    }
}
#endif
