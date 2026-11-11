#if canImport(UIKit)
import Foundation
import UIKit
import WebKit

// MARK: - MermaidRenderer (G4 C9, D2)

// NOTE: RemoteImagePipeline/G4: the transcript never mounts a live web view per diagram
// (§1.6.1, §0: at most 2 live WKWebViews). One shared offscreen view renders each unique
// diagram once, offscreen, into a cached UIImage; the card shows only the image. The
// full-screen live view is the artifact page (G5), leased from `WebViewSlotPool`.

/// What one offscreen mermaid render produced.
enum MermaidRenderOutcome: Sendable {
    /// The rendered SVG (for the live artifact view), the snapshot at screen scale, and
    /// the natural aspect ratio (for the reserved box).
    case diagram(image: UIImage, aspectRatio: CGFloat, svg: String)
    /// Mermaid refused the source: the card shows the source as code plus this string
    /// (upstream shows the source on syntax errors too).
    case error(message: String)
    /// No bundle, no scene, or the renderer never answered: nothing to show.
    case unavailable
}

/// The bundled mermaid runtime (11.16.0, MIT, `Resources/mermaid/`), run once per unique
/// diagram in a single shared offscreen `WKWebView`.
///
/// Protocol (kept deliberately close to upstream's runtime host): the document calls
/// `mermaid.render` a single time, then reports `{svg, width, height}` (or `{error}`)
/// through the `mermaidDone` script-message handler. No polling, no sleeps for content:
/// the snapshot waits for two animation frames after the render lands, then takes the
/// frame at its natural size. The web view, CSP (`connect-src 'none'`) and
/// `securityLevel: 'strict'` keep untrusted diagram source from reaching the network.
@MainActor
final class MermaidSnapshotRenderer: NSObject {
    static let shared = MermaidSnapshotRenderer()

    private var window: UIWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<MermaidSnapshot, Never>?
    private var runtimeScript: String?

    /// The message the render document posts when mermaid resolves or rejects.
    private struct MermaidSnapshot: Sendable {
        var svg: String?
        var width: CGFloat
        var height: CGFloat
        var error: String?
    }

    /// Renders `source` at `slotWidth` points and returns the snapshot, or the error.
    /// Serialized by `MermaidRenderQueue`: one offscreen render at a time.
    func render(source: String, dark: Bool, slotWidth: CGFloat) async -> MermaidRenderOutcome {
        guard slotWidth > 1, let webView = ensureWebView(), let script = runtime() else {
            return .unavailable
        }
        let html = Self.document(source: source, script: script, dark: dark)
        // A phone-height frame parked off screen; resized to the natural size after the
        // render reports it. The snapshot, not a live view, is what the transcript shows.
        webView.frame = CGRect(x: 0, y: 0, width: slotWidth, height: 1)
        window?.frame = CGRect(x: -10_000, y: -10_000, width: slotWidth, height: 1)
        // Single-flight: the queue guarantees no overlapping render owns
        // `self.continuation`.
        return await renderLoaded(html: html, in: webView)
    }

    /// The load-and-wait half: resolves when the document posts its result, or errors on
    /// timeout or navigation failure.
    private func renderLoaded(html: String, in webView: WKWebView) async -> MermaidRenderOutcome {
        let snapshot: MermaidSnapshot = await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
            Task {
                try? await Task.sleep(for: .seconds(20))
                self.finish(with: MermaidSnapshot(
                    svg: nil, width: 0, height: 0, error: "The diagram took too long to render."))
            }
        }
        if let message = snapshot.error, snapshot.svg == nil {
            return .error(message)
        }
        guard let svg = snapshot.svg, snapshot.width > 0, snapshot.height > 0 else {
            return .unavailable
        }
        // Lay the frame out at the natural size, wait two frames (event-driven, not a
        // sleep), then snapshot at screen scale like the SVG path does.
        let natural = CGSize(width: snapshot.width, height: snapshot.height)
        webView.frame = CGRect(origin: .zero, size: natural)
        _ = try? await webView.evaluateJavaScript(
            "new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))")
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: natural)
        configuration.snapshotWidth = NSNumber(value: Double(min(natural.width, 1365)))
        guard let image = try? await webView.takeSnapshot(configuration: configuration) else {
            return .unavailable
        }
        return .diagram(image: image, aspectRatio: natural.width / natural.height, svg: svg)
    }

    private func finish(with snapshot: MermaidSnapshot) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: snapshot)
    }

    // MARK: Document

    private func runtime() -> String? {
        if let runtimeScript { return runtimeScript }
        guard
            let url = Bundle.module.url(
                forResource: "mermaid.min", withExtension: "js", subdirectory: "mermaid"),
            let script = try? String(contentsOf: url, encoding: .utf8), !script.isEmpty
        else { return nil }
        runtimeScript = script
        return script
    }

    /// The single render document: the pinned runtime inline (offline, no file URLs to
    /// coordinate), the source JSON-encoded, one `mermaid.render` call, one result post.
    /// Upstream's `html.gen.ts` builds the same shape with esbuild; ours inlines the
    /// prebuilt file instead of bundling at build time.
    private static func document(source: String, script: String, dark: Bool) -> String {
        let escaped = source.replacingOccurrences(
            of: "</script", with: "<\\/script", options: .caseInsensitive)
        let encoded =
            (try? JSONEncoder().encode(escaped)).flatMap { String(data: $0, encoding: .utf8) }
            ?? "\"\""
        let theme = dark ? "dark" : "default"
        return """
            <!DOCTYPE html><html><head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
            <style>html,body{margin:0;padding:0;background:transparent}</style>
            </head><body>
            <div id="stage"></div>
            <script>\(script)</script>
            <script>(function(){var post=function(m){if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.mermaidDone){window.webkit.messageHandlers.mermaidDone.postMessage(m);}};try{mermaid.initialize({startOnLoad:false,securityLevel:'strict',suppressErrorRendering:true,theme:'\(theme)',flowchart:{htmlLabels:false}});mermaid.render('paseo-diagram',\(encoded)).then(function(r){document.getElementById('stage').innerHTML=r.svg;var svg=document.querySelector('#stage svg');var w=0,h=0;try{var vb=svg.viewBox.baseVal;if(vb&&vb.width>0&&vb.height>0){w=vb.width;h=vb.height;}}catch(e){}if(!(w>0&&h>0)){var b=svg.getBoundingClientRect();w=b.width;h=b.height;}post({svg:r.svg,width:w,height:h});},function(e){post({error:String((e&&e.message)||e)});});}catch(e){post({error:String((e&&e.message)||e)});}})();</script>
            </body></html>
            """
    }

    // MARK: Web view

    private func ensureWebView() -> WKWebView? {
        if let webView { return webView }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        else { return nil }
        let userContent = WKUserContentController()
        userContent.add(self, name: "mermaidDone")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContent
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        view.navigationDelegate = self
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.backgroundColor = .clear
        view.isInspectable = false
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -10_000, y: -10_000, width: 1, height: 1)
        window.windowLevel = .normal - 1
        window.backgroundColor = .clear
        window.addSubview(view)
        window.isHidden = false
        self.window = window
        self.webView = view
        return view
    }
}

extension MermaidSnapshotRenderer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: MermaidSnapshotRenderer.MermaidSnapshot(
            svg: nil, width: 0, height: 0, error: error.localizedDescription))
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(with: MermaidSnapshotRenderer.MermaidSnapshot(
            svg: nil, width: 0, height: 0, error: error.localizedDescription))
    }

    /// Only the document itself may load: a link tap or a redirect is cancelled, as in the
    /// sandboxed card.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        if navigationAction.navigationType == .linkActivated { return .cancel }
        if navigationAction.targetFrame == nil { return .cancel }
        return .allow
    }
}

extension MermaidSnapshotRenderer: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard message.name == "mermaidDone",
            let body = message.body as? [String: Any]
        else { return }
        let svg = body["svg"] as? String
        let width = (body["width"] as? NSNumber)?.doubleValue ?? 0
        let height = (body["height"] as? NSNumber)?.doubleValue ?? 0
        let error = body["error"] as? String
        finish(with: MermaidSnapshot(
            svg: svg, width: CGFloat(width), height: CGFloat(height), error: error))
    }
}

/// Serializes mermaid renders: one offscreen render at a time, in the order asked for.
/// It is main-actor rather than an `actor` because its resource (`WKWebView`) is main-actor
/// bound; the queueing guarantee is the same.
@MainActor
final class MermaidRenderQueue {
    static let shared = MermaidRenderQueue()
    private var tail: Task<Void, Never>?

    func render(source: String, dark: Bool, slotWidth: CGFloat) async -> MermaidRenderOutcome {
        let previous = tail
        let result: MermaidRenderOutcome = await withCheckedContinuation { continuation in
            let task = Task { @MainActor in
                _ = await previous?.value
                let outcome = await MermaidSnapshotRenderer.shared.render(
                    source: source, dark: dark, slotWidth: slotWidth)
                continuation.resume(returning: outcome)
            }
            tail = task
        }
        return result
    }
}
#endif
