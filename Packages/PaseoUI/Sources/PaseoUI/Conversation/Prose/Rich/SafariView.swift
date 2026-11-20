#if canImport(UIKit)
import PaseoStore
import SafariServices
import SwiftUI
import UIKit
import WebKit

/// Wraps `SFSafariViewController` for the "open in Safari view" behavior of rich cards.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
