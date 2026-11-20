#if canImport(UIKit)
import AVFoundation
import PaseoStore
import SwiftUI
import UIKit
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
#endif
