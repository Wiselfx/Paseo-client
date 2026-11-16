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

// MARK: - Scan

/// QR scan via VisionKit (`DataScannerViewController`, QR only). One attempt at a time:
/// the first payload that looks like a pairing link stops recognizing and is handed back.
public struct PairScanSheet: View {
    /// Called once with the accepted raw payload. Nil means the user closed.
    public var onScanned: (String) -> Void
    /// Offer Paste instead of scanning (permission denied or unavailable).
    public var onUsePaste: (() -> Void)?

    public init(onScanned: @escaping (String) -> Void, onUsePaste: (() -> Void)? = nil) {
        self.onScanned = onScanned
        self.onUsePaste = onUsePaste
    }
    @Environment(\.dismiss) private var dismiss

    @State private var failed = false
    @State private var permissionDenied = false
    @State private var granted = false
    @State private var didAccept = false

    public var body: some View {
        SheetScaffold("Scan QR", detents: .large) {
            if permissionDenied {
                concernContent(
                    title: "Camera permission",
                    body: "Allow camera access to scan the pairing QR code from your host.",
                    pasteHint: "Or paste the pairing link instead.")
            } else if failed {
                concernContent(
                    title: "QR scanning isn't available on this device.",
                    body: nil,
                    pasteHint: "Paste the pairing link instead.")
            } else {
                QRScannerView(
                    onPayload: { payload in
                        guard !didAccept else { return }
                        guard
                            payload.contains("#offer=") || payload.contains("#connect=")
                                || payload.hasPrefix("relay://")
                        else { return }
                        didAccept = true
                        onScanned(payload)
                    },
                    onFailed: { failed = true },
                    startWhen: granted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Point the camera at the pairing QR code.")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.vertical, 10)
            }
        }
        .onAppear {
            Task {
                guard DataScannerViewController.isSupported else {
                    failed = true
                    return
                }
                guard DataScannerViewController.isAvailable else {
                    failed = true
                    return
                }
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                switch status {
                case .denied, .restricted: permissionDenied = true
                case .authorized: granted = true
                case .notDetermined:
                    let grantedAccess = await AVCaptureDevice.requestAccess(for: .video)
                    if grantedAccess { granted = true } else { permissionDenied = true }
                @unknown default: failed = true
                }
                if !DataScannerViewController.isSupported {
                    failed = true
                }
            }
        }
    }

    @ViewBuilder
    private func concernContent(title: String, body: String?, pasteHint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.paseo(title.count > 30 ? .callout : .body, weight: .semibold))
            if let body {
                Text(body)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
            }
            if let onUsePaste {
                Button(pasteHint) { onUsePaste() }
                    .font(.paseo(.callout, weight: .medium))
                    .buttonStyle(.bordered)
            } else {
                Text(pasteHint)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        Spacer()
    }
}

/// VisionKit QR scanner, wrapped. Tap-to-scan and add-detection both feed it; the first
/// accepted payload stops scanning (one attempt at a time). Scanning starts once
/// `startWhen` flips true (the sheet only sets it after camera permission is confirmed);
/// `startScanning()` throws when the scanner is unavailable, which funnels to `onFailed`.
struct QRScannerView: UIViewControllerRepresentable {
    var onPayload: (String) -> Void
    /// Fired when scanning cannot start (unsupported, unavailable, permission).
    var onFailed: () -> Void
    /// Flips true once camera permission is confirmed; recognition begins then.
    var startWhen: Bool

    init(
        onPayload: @escaping (String) -> Void, onFailed: @escaping () -> Void = {},
        startWhen: Bool = false
    ) {
        self.onPayload = onPayload
        self.onFailed = onFailed
        self.startWhen = startWhen
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        context.coordinator.attach(scanner)
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if startWhen { context.coordinator.beginScanning() }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload, onFailed: onFailed)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPayload: (String) -> Void
        let onFailed: () -> Void
        private weak var scanner: DataScannerViewController?
        private var reported = false
        private var started = false

        init(onPayload: @escaping (String) -> Void, onFailed: @escaping () -> Void) {
            self.onPayload = onPayload
            self.onFailed = onFailed
        }

        func attach(_ scanner: DataScannerViewController) {
            self.scanner = scanner
        }

        func beginScanning() {
            // Recognition never delivers without this; it throws when the scanner is
            // unavailable or permissions are missing, which the sheet turns into Paste.
            guard !reported, !started else { return }
            started = true
            do {
                try scanner?.startScanning()
            } catch {
                reportFailure()
            }
        }

        func reportFailure() {
            guard !reported else { return }
            reported = true
            Task { @MainActor in self.onFailed() }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            reportFailure()
        }

        /// Point-at-the-code detection (the natural scan path).
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]
        ) {
            guard let first = addedItems.first,
                case .barcode(let barcode) = first,
                let payload = barcode.payloadStringValue
            else { return }
            dataScanner.stopScanning()
            Task { @MainActor in self.onPayload(payload) }
        }

        /// Tap-to-scan path.
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case .barcode(let barcode) = item,
                let payload = barcode.payloadStringValue
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
    /// A failure from the last attempt (parse or connect), shown when the paste step is
    /// re-presented with the error (S6).
    public var error: String?
    /// Called once with the accepted raw payload, already trimmed.
    public var onPasted: (String) -> Void

    public init(error: String? = nil, onPasted: @escaping (String) -> Void) {
        self.error = error
        self.onPasted = onPasted
    }
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var invalid = false

    public var body: some View {
        SheetScaffold("Paste pairing link", detents: .large) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Treat this pairing link like a password. Anyone with it can access this host.")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                // Prompt-free PasteButton (system label): reads the pasteboard on tap.
                PasteButton(payloadType: String.self) { strings in
                    text = strings.first ?? ""
                    invalid = false
                    submit()
                }
                .font(.paseo(.callout, weight: .medium))
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pairing.paste.button")
                TextField("Pairing link", text: $text)
                    .font(.paseo(.callout))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Palette.chip, in: .rect(cornerRadius: Radius.md))
                    .onSubmit { submit() }
                    .accessibilityIdentifier("pairing.paste.field")
                Button {
                    submit()
                } label: {
                    Text("Connect")
                        .font(.paseo(.callout, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.ink)
                .accessibilityIdentifier("pairing.paste.connect")
                if invalid {
                    Text("That link doesn't look right.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                }
                if let error, !invalid {
                    Text(error)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
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
    /// True while a connect attempt is in flight: Connect is disabled (one attempt at a
    /// time, S1), with a spinner in place of the label.
    public var isAttempting: Bool
    public var onConnect: () -> Void

    public init(
        offer: ConnectionOffer, kind: HostConfirmationKind, isAttempting: Bool = false,
        onConnect: @escaping () -> Void
    ) {
        self.offer = offer
        self.kind = kind
        self.isAttempting = isAttempting
        self.onConnect = onConnect
    }
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        SheetScaffold("Connect to this host?", detents: .large) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(kind == .changedConnection
                        ? "This link changes how you connect to this host. The host will be able to run code in this app and reach your other connected hosts. Only connect if you recognize it."
                        : "This host will be able to run code in this app and reach your other connected hosts. Only connect if you recognize it.")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
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
                            .font(.paseo(.callout, weight: .medium))
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("pairing.confirm.cancel")
                        Button {
                            onConnect()
                        } label: {
                            if isAttempting {
                                ProgressView().controlSize(.small).tint(Palette.background)
                            } else {
                                Text("Connect")
                            }
                        }
                        .font(.paseo(.callout, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.ink)
                        .frame(maxWidth: .infinity)
                        .disabled(isAttempting)
                        .accessibilityIdentifier("pairing.confirm.connect")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.paseo(.callout))
            Spacer(minLength: 8)
            Text(value)
                .font(.paseo(.code))
                .foregroundStyle(Palette.secondaryInk)
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
