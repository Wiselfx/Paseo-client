#if canImport(UIKit)
import PaseoStore
import SafariServices
import SwiftUI
import UIKit
import WebKit

/// The checkout a file preview reads its relative references from.
struct PreviewFileSource {
    let files: WorkspaceFiles
    let workspaceId: String
}

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
/// height through the `vizHeight` script message handler, which debounces, clamps and
/// forwards to `onHeightChange`, plus whether the content still exceeds the ceiling. Navigation
/// policy allows only non-link loads: taps on links are cancelled, and the documents carry a
/// no-network CSP, so rich cards never make a request a reader didn't ask for.
struct SandboxedHTMLView: UIViewRepresentable {
    let html: String
    let heightFloor: CGFloat
    let heightCeiling: CGFloat
    var onHeightChange: (CGFloat) -> Void
    /// True when the reported content is taller than `heightCeiling`: the card offers "Open".
    var onOverflowChange: ((Bool) -> Void)? = nil
    /// A file preview is a document, not a rich card: it fills its frame and scrolls. Rich cards
    /// keep the default (sized to their reported content height).
    var fillsFrame: Bool = false
    /// File previews render the workspace's own markup; scripts are on (a static page is blank)
    /// in a non-persistent data store, and navigation away opens in Safari.
    var allowsScripts: Bool = true
    /// Called for a top-level navigation that isn't the document itself (a link tap, a form
    /// post, a redirect). File previews open the URL in an in-app Safari sheet instead.
    var onExternalNavigation: ((URL) -> Void)? = nil
    /// The workspace a file preview may read through `paseo-file://`; nil for chat cards, which
    /// have no access to workspace files. The scheme handler is built with the web view, so no
    /// object is allocated per `body` pass.
    var previewFiles: PreviewFileSource? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange, floor: heightFloor, ceiling: heightCeiling)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "vizHeight")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = allowsScripts
        if allowsScripts {
            // A preview of the user's own file: nothing to persist, nothing shared with the app.
            configuration.websiteDataStore = .nonPersistent()
            configuration.allowsInlineMediaPlayback = true
        }
        if let previewFiles {
            configuration.setURLSchemeHandler(
                WorkspacePreviewFileHandler(
                    files: previewFiles.files, workspaceId: previewFiles.workspaceId),
                forURLScheme: PreviewFileScheme.name)
        }
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
        context.coordinator.onOverflowChange = onOverflowChange
        context.coordinator.onExternalNavigation = onExternalNavigation
        context.coordinator.floor = heightFloor
        context.coordinator.ceiling = heightCeiling
        context.coordinator.allowsExternalNavigation = onExternalNavigation != nil
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
        var onOverflowChange: ((Bool) -> Void)?
        var onExternalNavigation: ((URL) -> Void)?
        var allowsExternalNavigation = false
        var floor: CGFloat
        var ceiling: CGFloat
        var loadedHTML: String?

        /// The last height handed to `onHeightChange`; reports closer than 2 pt are ignored.
        private var lastHeight: CGFloat?
        private var reportedOverflow = false
        /// Debounces the height reporter: scripts lay out in bursts, and one animated height
        /// change when they settle beats a jump per burst.
        private var pendingReport: Task<Void, Never>?

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
            scheduleReport(CGFloat(value))
        }

        private func scheduleReport(_ raw: CGFloat) {
            pendingReport?.cancel()
            pendingReport = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                self.publish(raw)
            }
        }

        private func publish(_ raw: CGFloat) {
            let height = min(max(raw, floor), ceiling)
            let overflows = raw > ceiling
            if overflows != reportedOverflow {
                reportedOverflow = overflows
                onOverflowChange?(overflows)
            }
            // Sub-2-pt moves are layout noise; ignore them so the card never jitters.
            if let lastHeight, abs(lastHeight - height) < 2 { return }
            lastHeight = height
            onHeightChange(height)
        }

        /// The first main-frame load is the document itself and is allowed; every later one (a
        /// link, a form post, a redirect) is cancelled — or, for a file preview, handed to Safari.
        /// Sub-frames are part of the document and load normally.
        private var loadedDocument = false

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let target = navigationAction.targetFrame else {
                // A new window: `target="_blank"`. A preview opens it in Safari.
                if allowsExternalNavigation, let url = navigationAction.request.url {
                    onExternalNavigation?(url)
                }
                return .cancel
            }
            if !target.isMainFrame { return .allow }
            if !loadedDocument {
                loadedDocument = true
                return .allow
            }
            if let url = navigationAction.request.url {
                // A link inside the preview that points at the workspace: never hand a synthetic
                // scheme to Safari. Subresources arrive through the scheme handler, not here.
                if url.scheme?.lowercased() == PreviewFileScheme.name { return .cancel }
                if allowsExternalNavigation { onExternalNavigation?(url) }
            }
            return .cancel
        }
    }
}

/// HTML documents for the two web-backed rich blocks. Both are offline: the CSP forbids
/// every source except inline styles/scripts (viz) or nothing at all (SVG), and image
/// loads to data:/blob: URLs. Theme vars follow docs/research/05-rich-media-spec.md §2:
/// `--viz-fg`, `--viz-bg`, `--viz-accent`.
enum RichHTMLDocument {
    /// Reports the document's height once per animation frame and only when it moved by half a
    /// point or more (R9 §2). A `ResizeObserver` on the body replaces the whole-document
    /// `MutationObserver` where it exists; the observer is only the fallback.
    private static let heightReporter = """
        <script>(function(){var last=-1,queued=false;function post(){queued=false;var t=document.documentElement,b=document.body;var h=Math.max(t?t.scrollHeight:0,b?b.scrollHeight:0);if(Math.abs(h-last)<0.5)return;last=h;if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.vizHeight){window.webkit.messageHandlers.vizHeight.postMessage(h);}}function schedule(){if(queued)return;queued=true;requestAnimationFrame(post);}if(window.ResizeObserver){new ResizeObserver(schedule).observe(document.documentElement);if(document.body)new ResizeObserver(schedule).observe(document.body);if(document.documentElement.firstElementChild)new ResizeObserver(schedule).observe(document.documentElement.firstElementChild);}else{new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true,attributes:true,characterData:true});}window.addEventListener('load',schedule);schedule();})();</script>
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

    /// A rendered artifact SVG (mermaid output, G4/G5): the same static guarantees as the
    /// raw block, but sized for a full-screen page instead of a card — the drawing fills
    /// the viewport width at its intrinsic ratio and the page scrolls what exceeds it.
    /// No height reporter: the page is not sized to its content.
    static func artifactSVG(source: String, dark: Bool) -> String {
        let scheme = dark ? "dark" : "light"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
        <style>:root { color-scheme: \(scheme); }
        html, body { margin: 0; padding: 0; background: transparent; }
        svg { width: 100%; height: auto; display: block; }
        </style>
        </head>
        <body>
        \(source)
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
        /* Full width: a viewBox-only <svg> is 300x150 by default and would letterbox inside
           the card. height:auto follows the intrinsic ratio from the viewBox or the
           width/height attributes. */
        svg { width: 100%; height: auto; display: block; }
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
