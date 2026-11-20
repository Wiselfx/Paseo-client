#if canImport(UIKit)
import PaseoStore
import SafariServices
import SwiftUI
import UIKit
import WebKit

/// Wraps `UIActivityViewController` for the full-screen image share action.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
