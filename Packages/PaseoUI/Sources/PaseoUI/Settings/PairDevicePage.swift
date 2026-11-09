#if canImport(UIKit)
import CoreImage
import CoreImage.CIFilterBuiltins
import PaseoStore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Settings → Host → "Pair a device": renders the daemon's pairing offer as a QR the phone
/// scans, with the copyable link beside it. Upstream is Paseo Desktop's
/// `pair-device-section.tsx`; every user-facing string below cites its `en.ts` line
/// (`pairing.device.*` at en.ts:1968-1993, row title at en.ts:2916, Cancel at en.ts:31).
///
/// The offer URL is a credential: it lives only in store state until this page closes
/// (`clearPairingOffer()` on disappear), it is never logged, and the Copy button marks the
/// pasteboard local-only with a short expiration.
struct PairDevicePage: View {
    let session: HostSession

    @State private var copied = false
    @State private var confirmEnableRelay = false
    @State private var enableFailed: String?

    private let typography = ClaudeTypography()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Pair device")
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .task {
            if case .idle = session.hostSettings.pairingOfferState {
                await session.hostSettings.loadPairingOffer()
            }
        }
        .onDisappear {
            session.hostSettings.clearPairingOffer()
        }
        .confirmationDialog(
            // en.ts:1972 enableTitle
            "Enable relay?",
            isPresented: $confirmEnableRelay,
            titleVisibility: .visible
        ) {
            // en.ts:1977 enableRelay
            Button("Enable relay") {
                Task { await enableRelay() }
            }
            // en.ts:1979 notNow
            Button("Not now", role: .cancel) {}
        } message: {
            // en.ts:1973-1974 enableDescription
            Text("Relay lets this device connect from anywhere. Pairing traffic is end-to-end encrypted.")
        }
    }

    @ViewBuilder private var content: some View {
        switch session.hostSettings.pairingOfferState {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                // en.ts:1969 loadingOffer
                Text("Loading pairing offer...")
                    .font(.system(size: 15))
                    .foregroundStyle(ClaudePalette.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                // en.ts:1970 failedToLoadOffer
                Text("Failed to load pairing offer.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                // en.ts:1991 retry
                Button("Retry") {
                    Task { await session.hostSettings.loadPairingOffer() }
                }
                .font(.system(size: 15, weight: .medium))
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pairDevice.retry")
            }
        case .received(let url, let relayEnabled):
            if relayEnabled, !url.isEmpty {
                offerContent(url: url)
            } else {
                relayDisabledContent
            }
        }
    }

    private func offerContent(url: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // en.ts:1986 hint
            Text("Scan this QR code with Paseo on your phone, or copy the link below.")
                .font(.system(size: 15))
                .foregroundStyle(ClaudePalette.secondaryInk)
            if let qr = Self.qrImage(for: url) {
                Image(uiImage: qr)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Pairing QR code") // en.ts:1990 qrAccessibility
            } else {
                // en.ts:1989 qrUnavailable
                Text("QR code unavailable.")
                    .font(.system(size: 14))
                    .foregroundStyle(ClaudePalette.secondaryInk)
            }
            HStack(spacing: 8) {
                Text(url)
                    .font(typography.mono(12))
                    .foregroundStyle(ClaudePalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                Button {
                    Haptics.selection()
                    Self.copy(url: url)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    // en.ts:1992 copy / en.ts:1993 copied
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pairDevice.copy")
            }
            // en.ts:1987-1988 securityWarning
            Text("Treat this pairing link like a password. Anyone with it can access this daemon.")
                .font(.system(size: 13))
                .foregroundStyle(ClaudePalette.secondary)
        }
    }

    private var relayDisabledContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // en.ts:1971 relayDisabled
            Text("Relay is not enabled. Enable relay to pair a device.")
                .font(.system(size: 15))
                .foregroundStyle(ClaudePalette.secondaryInk)
            if session.hostSettings.supportsRelayConfig {
                Button {
                    confirmEnableRelay = true
                } label: {
                    // en.ts:1977 enableRelay
                    Text("Enable relay")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ClaudePalette.ink)
                .accessibilityIdentifier("pairDevice.enableRelay")
            } else {
                // en.ts:1984 updateRequired
                Text("Update the host to enable relay from Paseo Desktop.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
            }
            if let enableFailed, !enableFailed.isEmpty {
                Text(enableFailed)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.failureInk)
            }
        }
    }

    private func enableRelay() async {
        enableFailed = nil
        guard await session.hostSettings.enableRelay() else {
            // hostSettings.error already carries the daemon's wording.
            enableFailed = session.hostSettings.error
            return
        }
        await session.hostSettings.loadPairingOffer()
    }

    /// Crisp QR: scaled with nearest-neighbour interpolation, error correction M
    /// (upstream `QRCode.toString(..., { errorCorrectionLevel: "M", margin: 1 })`,
    /// pair-device-section.tsx:78-89).
    nonisolated static func qrImage(for url: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        guard
            let cg = context.createCGImage(
                output.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
                from: output.extent)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Local-only pasteboard with a short expiration: the link never leaves this device
    /// (no iCloud clipboard) and dies two minutes later.
    private static func copy(url: String) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: url]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15))
            .foregroundStyle(ClaudePalette.secondary)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }
}
#endif
