#if canImport(UIKit)
import AVFoundation
import PaseoStore
import SwiftUI
import UIKit
import VisionKit

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
    @Environment(\.dismiss) private var dismiss

    public init(onDirect: @escaping () -> Void, onScan: @escaping () -> Void, onPaste: @escaping () -> Void) {
        self.onDirect = onDirect
        self.onScan = onScan
        self.onPaste = onPaste
    }

    public var body: some View {
        SheetScaffold("Add connection", detents: .large) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    methodRow(
                        title: "Direct connection", description: "Local network or VPN.",
                        symbol: "link", id: "pairing.direct")
                    { onDirect() }
                    methodRow(
                        title: "Scan QR code", description: "Encrypted relay connection.",
                        symbol: "qrcode.viewfinder", id: "pairing.scan")
                    { onScan() }
                    methodRow(
                        title: "Paste pairing link", description: "Encrypted relay connection.",
                        symbol: "clipboard", id: "pairing.paste")
                    { onPaste() }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func methodRow(
        title: String, description: String, symbol: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 30, height: 30)
                    .background(Palette.chip, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.paseo(.body, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(description)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.glyph(.regular))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60, alignment: .leading)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
#endif
