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
public enum PairingConnectOutcome {
    case connected
    case passwordRequired
    case failed(String)
}

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

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Add connection") { dismiss() }
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
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
    }

    private func methodRow(
        title: String, description: String, symbol: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(ClaudePalette.ink)
                    .frame(width: 30, height: 30)
                    .background(ClaudePalette.chip, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15))
                    .foregroundStyle(ClaudePalette.secondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60, alignment: .leading)
            .background(ClaudePalette.panel, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Scan

/// QR scan via VisionKit (`DataScannerViewController`, QR only). One attempt at a time:
/// the first payload that looks like a pairing link stops recognizing and is handed back.
public struct PairScanSheet: View {
    /// Called once with the accepted raw payload. Nil means the user closed.
    public var onScanned: (String) -> Void

    public init(onScanned: @escaping (String) -> Void) {
        self.onScanned = onScanned
    }
    @Environment(\.dismiss) private var dismiss

    @State private var failed = false
    @State private var permissionDenied = false
    @State private var didAccept = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Scan QR") { dismiss() }
            if permissionDenied {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Camera permission")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Allow camera access to scan the pairing QR code from your daemon.")
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    Text("Or paste the pairing link instead.")
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                Spacer()
            } else if failed {
                VStack(alignment: .leading, spacing: 10) {
                    Text("QR scanning isn't available on this device.")
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    Text("Paste the pairing link instead.")
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                Spacer()
            } else {
                QRScannerView { payload in
                    guard !didAccept else { return }
                    guard
                        payload.contains("#offer=") || payload.contains("#connect=")
                            || payload.hasPrefix("relay://")
                    else { return }
                    didAccept = true
                    onScanned(payload)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Point the camera at the pairing QR code.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.vertical, 10)
            }
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .onAppear {
            Task {
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                switch status {
                case .denied, .restricted: permissionDenied = true
                case .authorized: break
                case .notDetermined:
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    if !granted { permissionDenied = true }
                @unknown default: failed = true
                }
                if !DataScannerViewController.isSupported {
                    failed = true
                }
            }
        }
    }
}

/// VisionKit QR scanner, wrapped. Callback mode (`qualityLevel .balanced`, QR only).
public struct QRScannerView: UIViewControllerRepresentable {
    public var onPayload: (String) -> Void

    public init(onPayload: @escaping (String) -> Void) {
        self.onPayload = onPayload
    }

    public func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            qualityLevel: .balanced, recognizesDocuments: false)
        scanner.delegate = context.coordinator
        return scanner
    }

    public func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPayload: (String) -> Void

        init(onPayload: @escaping (String) -> Void) {
            self.onPayload = onPayload
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapWith barcodeItems: [RecognizedBarcodeItem]
        ) {
            guard let first = barcodeItems.first,
                let payload = first.payloadValue
            else { return }
            dataScanner.stopScanning()
            Task { @MainActor in self.onPayload(payload) }
        }
    }
}

// MARK: - Paste

/// Paste a pairing link: `PasteButton` (no pasteboard prompt) or a text field, through the
/// same offer parser as scan. The link is never logged.
public struct PastePairingSheet: View {
    /// Called once with the accepted raw payload, already trimmed.
    public var onPasted: (String) -> Void

    public init(onPasted: @escaping (String) -> Void) {
        self.onPasted = onPasted
    }
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Paste pairing link") { dismiss() }
            VStack(alignment: .leading, spacing: 12) {
                Text("Treat this pairing link like a password. Anyone with it can access this daemon.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                // Prompt-free: PasteButton reads the pasteboard on tap, no system prompt.
                PasteButton("Paste link") { pasted in
                    text = pasted
                    invalid = false
                    submit()
                }
                .font(.system(size: 15, weight: .medium))
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pairing.paste.button")
                TextField("Pairing link", text: $text)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(ClaudePalette.chip, in: .rect(cornerRadius: 12))
                    .onSubmit { submit() }
                    .accessibilityIdentifier("pairing.paste.field")
                Button {
                    submit()
                } label: {
                    Text("Connect")
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ClaudePalette.ink)
                .accessibilityIdentifier("pairing.paste.connect")
                if invalid {
                    Text("That link doesn't look right.")
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.failureInk)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Same acceptance rule as the scanner; the parse itself happens on Connect.
        guard trimmed.contains("#offer=") || trimmed.contains("#connect=")
            || trimmed.hasPrefix("relay://") else {
            invalid = true
            return
        }
        onPasted(trimmed)
    }
}

// MARK: - Confirmation

/// "Connect to this host?" with the three rows (Host = serverId, Key fingerprint, Relay =
/// endpoint), upstream wording verbatim. Exact-match links never reach here.
public struct HostConfirmationPairingSheet: View {
    public let offer: ConnectionOffer
    public let kind: HostConfirmationKind
    public var onConnect: () -> Void

    public init(offer: ConnectionOffer, kind: HostConfirmationKind, onConnect: @escaping () -> Void) {
        self.offer = offer
        self.kind = kind
        self.onConnect = onConnect
    }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Connect to this host?") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(kind == .changedConnection
                        ? "This link changes how you connect to this host. The host will be able to run code in this app and reach your other connected hosts. Only connect if you recognize it."
                        : "This host will be able to run code in this app and reach your other connected hosts. Only connect if you recognize it.")
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    RowGroup {
                        detailRow(label: "Host", value: offer.serverID)
                        RowDivider()
                        detailRow(
                            label: "Key fingerprint",
                            value: HostConfirmation.keyFingerprint(offer.daemonPublicKeyB64))
                        RowDivider()
                        detailRow(label: "Relay", value: offer.relayEndpoint)
                    }
                    HStack(spacing: 10) {
                        Button("Cancel") { dismiss() }
                            .font(.system(size: 15, weight: .medium))
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("pairing.confirm.cancel")
                        Button("Connect") {
                            Haptics.selection()
                            onConnect()
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(ClaudePalette.ink)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("pairing.confirm.connect")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 15))
            Spacer(minLength: 8)
            Text(value)
                .font(ClaudeTypography().mono(13))
                .foregroundStyle(ClaudePalette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52, alignment: .leading)
    }
}

// MARK: - Password

/// "Password for {host}" — shown only after the daemon rejected the (encrypted) hello for
/// password reasons (doc 11 §8.3). Never stored in plain settings: the Keychain on success.
public struct PairingPasswordSheet: View {
    public let host: String
    public var error: String?
    public var onConnect: (String) -> Void

    public init(host: String, error: String? = nil, onConnect: @escaping (String) -> Void) {
        self.host = host
        self.error = error
        self.onConnect = onConnect
    }
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Password for \(host)") { dismiss() }
            VStack(alignment: .leading, spacing: 12) {
                SecureField("Host password", text: $password)
                    .font(.system(size: 17))
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .background(ClaudePalette.chip, in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("pairing.password.field")
                if let error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.failureInk)
                }
                Button {
                    submit()
                } label: {
                    Text("Connect")
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ClaudePalette.ink)
                .disabled(password.isEmpty)
                .opacity(password.isEmpty ? 0.4 : 1)
                .accessibilityIdentifier("pairing.password.connect")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
    }

    private func submit() {
        guard !password.isEmpty else { return }
        onConnect(password)
    }
}
#endif
