#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// The inline player (E3 §3.4): `youtube-nocookie.com` embed in a one-line document whose
/// `baseURL` is an https origin, so YouTube sees a referrer (without one it refuses with error
/// 152/153). Inline playback, no gesture required to start, no page scroll.
///
/// Stays a `WKWebView` representable rather than SwiftUI's `WebView`/`WebPage`: as of iOS 26,
/// `WebPage.Configuration` has no equivalent of `mediaTypesRequiringUserActionForPlayback`, so
/// the embed could not autoplay after the card's tap and would need a second tap inside it.
struct InlineYouTubePlayer: UIViewRepresentable {
    let referenceID: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(Self.document(for: referenceID), baseURL: Self.origin)
        context.coordinator.loadedOrigin = Self.origin
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Leaving the hierarchy would usually be enough; stopping the load and dropping the
        // delegate makes sure the media session ends with the view.
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.pauseAllMediaPlayback {}
    }

    /// The referrer origin YouTube expects; the document itself is inline HTML.
    static let origin = URL(string: "https://www.youtube-nocookie.com")

    static func document(for id: String) -> String {
        // An id is alphanumerics plus `-`/`_`; anything else is dropped before it reaches markup.
        let embedID = id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return """
            <!DOCTYPE html><html><head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}
            iframe{border:0;display:block;width:100%;height:100%}</style>
            </head><body>
            <iframe src="https://www.youtube-nocookie.com/embed/\(embedID)?playsinline=1&autoplay=1&rel=0&modestbranding=1"
              allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
              allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>
            </body></html>
            """
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedOrigin: URL?

        /// The document load is allowed; a main-frame navigation away from it (YouTube's own
        /// "Watch on YouTube") is cancelled — the card's menu opens the app instead.
        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let frame = navigationAction.targetFrame, frame.isMainFrame else { return .allow }
            if navigationAction.navigationType == .other, loadedOrigin != nil { return .allow }
            return .cancel
        }
    }
}
#endif
