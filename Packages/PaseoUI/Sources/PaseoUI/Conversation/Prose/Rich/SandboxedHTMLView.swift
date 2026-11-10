#if canImport(UIKit)
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

/// Wraps `UIActivityViewController` for the full-screen image share action.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A sandboxed, non-scrollable `WKWebView` sized to its content.
///
/// The HTML document is built by the caller (`RichHTMLDocument`); it reports its content
/// height through the `vizHeight` script message handler, which this view clamps and
/// forwards to `onHeightChange`. Navigation policy allows only non-link loads: taps on
/// links are cancelled, and the documents carry a no-network CSP, so rich cards never
/// make a request a reader didn't ask for.
struct SandboxedHTMLView: UIViewRepresentable {
    let html: String
    let heightFloor: CGFloat
    let heightCeiling: CGFloat
    var onHeightChange: (CGFloat) -> Void
    /// A file preview is a document, not a rich card: it fills its frame and scrolls. Rich cards
    /// keep the default (sized to their reported content height).
    var fillsFrame: Bool = false
    /// File previews render untrusted markup with page JavaScript off. Rich cards need the
    /// height reporter, so they keep it on.
    var allowsScripts: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange, floor: heightFloor, ceiling: heightCeiling)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "vizHeight")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = allowsScripts
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = fillsFrame
        webView.scrollView.bounces = fillsFrame
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Pages here are fully static; there is no state the app needs inspection of.
        webView.isInspectable = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onHeightChange = onHeightChange
        context.coordinator.floor = heightFloor
        context.coordinator.ceiling = heightCeiling
        webView.scrollView.isScrollEnabled = fillsFrame
        webView.scrollView.bounces = fillsFrame
        if context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "vizHeight")
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onHeightChange: (CGFloat) -> Void
        var floor: CGFloat
        var ceiling: CGFloat
        var loadedHTML: String?

        init(onHeightChange: @escaping (CGFloat) -> Void, floor: CGFloat, ceiling: CGFloat) {
            self.onHeightChange = onHeightChange
            self.floor = floor
            self.ceiling = ceiling
        }

        func userContentController(
            _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            guard message.name == "vizHeight",
                let value = (message.body as? NSNumber)?.doubleValue ?? message.body as? Double
            else { return }
            onHeightChange(min(max(CGFloat(value), floor), ceiling))
        }

        // The initial document load is the only navigation allowed; everything the
        // content itself triggers (links, redirects) is cancelled.
        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated { return .cancel }
            if navigationAction.targetFrame == nil { return .cancel }
            return .allow
        }
    }
}

/// HTML documents for the two web-backed rich blocks. Both are offline: the CSP forbids
/// every source except inline styles/scripts (viz) or nothing at all (SVG), and image
/// loads to data:/blob: URLs. Theme vars follow docs/research/05-rich-media-spec.md §2:
/// `--viz-fg`, `--viz-bg`, `--viz-accent`.
enum RichHTMLDocument {
    private static let heightReporter = """
        <script>(function(){function r(){var t=document.documentElement,b=document.body;var h=Math.max(t?t.scrollHeight:0,b?b.scrollHeight:0);if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.vizHeight){window.webkit.messageHandlers.vizHeight.postMessage(h);}}new MutationObserver(r).observe(document.documentElement,{childList:true,subtree:true,attributes:true,characterData:true});window.addEventListener('load',r);r();})();</script>
        """

    /// The ` ```visualize ` fence: a self-contained HTML fragment in a sandboxed document.
    /// No network, no frames, no external anything; color scheme follows the app.
    static func visualize(code: String, dark: Bool) -> String {
        let fg = dark ? "#e6e6e6" : "#1a1a1a"
        let accent = dark ? "#7dd3fc" : "#0369a1"
        let scheme = dark ? "dark" : "light"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'">
        <style>:root { color-scheme: \(scheme); --viz-fg: \(fg); --viz-bg: transparent; --viz-accent: \(accent); }
        html, body { margin: 0; padding: 0; background: transparent; color: var(--viz-fg); font-family: -apple-system, sans-serif; }
        </style>
        </head>
        <body>
        \(code)
        \(heightReporter)
        </body>
        </html>
        """
    }

    /// A raw `<svg>…</svg>` block, inlined. Scripts never run: the CSP has no `script-src`,
    /// so inline SVG event handlers and `<script>` children are all blocked.
    static func rawSVG(source: String, dark: Bool) -> String {
        let scheme = dark ? "dark" : "light"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
        <style>:root { color-scheme: \(scheme); }
        html, body { margin: 0; padding: 0; background: transparent; }
        svg { max-width: 100%; height: auto; display: block; }
        </style>
        </head>
        <body>
        \(source)
        \(heightReporter)
        </body>
        </html>
        """
    }
}
#endif
