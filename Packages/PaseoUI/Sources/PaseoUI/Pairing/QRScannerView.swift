#if canImport(UIKit)
import AVFoundation
import PaseoStore
import SwiftUI
import UIKit
import VisionKit

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
#endif
