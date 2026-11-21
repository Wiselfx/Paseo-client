#if canImport(UIKit)
import AVFoundation
import SwiftUI
import VisionKit

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
                        guard PairingLink.looksValid(payload) else { return }
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
        .task { await prepareScanner() }
    }

    /// Checks the scanner and the camera permission; the sheet starts scanning once `granted`.
    private func prepareScanner() async {
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            failed = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: permissionDenied = true
        case .authorized: granted = true
        case .notDetermined:
            let grantedAccess = await AVCaptureDevice.requestAccess(for: .video)
            if grantedAccess { granted = true } else { permissionDenied = true }
        @unknown default: failed = true
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
#endif
