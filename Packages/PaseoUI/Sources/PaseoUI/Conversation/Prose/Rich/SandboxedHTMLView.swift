#if canImport(UIKit)
import PaseoStore
import SafariServices
import SwiftUI
import UIKit
import WebKit

/// A sandboxed, non-scrollable `WKWebView` sized to its content.
///
/// The HTML document is built by the caller (`RichHTMLDocument`); it reports its content
/// height through the `vizHeight` script message handler, which debounces, clamps and
/// forwards to `onHeightChange`, plus whether the content still exceeds the ceiling. The
/// height is published **once**, from the layout the document has after its first load:
/// later growth never re-flows the row that hosts the view (V2). Navigation
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
    /// The compiled offline rule list for chat documents (`OfflineContentRules`). Nil
    /// renders as today (Files previews keep their CDN access).
    var contentRuleList: WKContentRuleList? = nil
    /// When true the first load waits for the rule list: a chat document must never
    /// paint unprotected, even for the milliseconds the first compile takes.
    var awaitContentRules = false

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
        if context.coordinator.appliedRuleList !== contentRuleList {
            context.coordinator.appliedRuleList = contentRuleList
            webView.configuration.userContentController.removeAllContentRuleLists()
            if let contentRuleList {
                webView.configuration.userContentController.add(contentRuleList)
            }
        }
        let rulesReady = !awaitContentRules || contentRuleList != nil
        if rulesReady, context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            context.coordinator.loadedDocument = false
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
        /// The rule list currently installed on the web view; nil after a removal.
        /// Compared by identity: a new compile is a new object.
        var appliedRuleList: WKContentRuleList?

        private var reportedOverflow = false
        /// The document completed its first load (or failed to): only from then on is a
        /// reported height the page's real layout. Parse-time reports are noise.
        private var finishedFirstLoad = false
        /// One height per document. Later growth must not re-flow a transcript row.
        private var publishedHeight = false
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
            // After the one published height, only the overflow flag can still change; a
            // report that cannot change it is not worth a task (V2, no per-frame work).
            if publishedHeight, (raw > ceiling) == reportedOverflow { return }
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
            // V2: the card reserves the page's size once, from the layout it has after its
            // load. Every later report (a script adding rows, a font settling) is ignored:
            // content arriving must never move the row or the scroll position.
            guard finishedFirstLoad, !publishedHeight else { return }
            publishedHeight = true
            onHeightChange(height)
        }

        func webView(
            _ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            // A new document measures itself once too (a reload, a scheme rebuild). The card
            // ignores repeats, so this never re-flows a row.
            finishedFirstLoad = false
            publishedHeight = false
            pendingReport?.cancel()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finishedFirstLoad = true
        }

        func webView(
            _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
        ) {
            finishedFirstLoad = true
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            finishedFirstLoad = true
        }

        /// The first main-frame load is the document itself and is allowed; every later one (a
        /// link, a form post, a redirect) is cancelled — or, for a file preview, handed to Safari.
        /// Sub-frames are part of the document and load normally. `updateUIView` resets it before
        /// each `loadHTMLString`, so a reload or a scheme rebuild is the document again, not a
        /// link to cancel.
        var loadedDocument = false

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
#endif
