#if canImport(UIKit)
import OSLog
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// The one offscreen `WKWebView` for the whole transcript (G4 §4.1, §0 web-view budget:
/// 2 live pooled slots + this 1 offscreen renderer, in the single parked window).
///
/// SVG blocks used to mount a live `WKWebView` each. A static drawing does not need one: it is
/// rendered once at display width, cached by content, and drawn as an image; the full-screen
/// viewer zooms that image (E3 §3.1). Rasterising beats a live view because the result is a
/// plain `UIImage`: no web process per card, no per-scroll work, and crisp at
/// `displayScale` because WebKit snapshots at the screen scale. Mermaid diagrams render
/// through the same view and the same serial queue: the pinned runtime stays loaded in
/// its host document and is reloaded only after an SVG job replaced it (rare once the
/// transcript's snapshots are warm, since every diagram renders once per scheme).
///
/// The web view lives in a 1 pt window parked off screen — `takeSnapshot(with:)` only renders
/// views that are in a window hierarchy. JavaScript is on (mermaid needs it) but the SVG
/// documents' CSP has no `script-src`, so nothing there can run; the mermaid host runs
/// only the pinned runtime with `connect-src 'none'`, and chat pages get the compiled
/// content-rule list on top (`OfflineContentRules`).
@MainActor
final class RichWebSnapshotRenderer: NSObject, WKNavigationDelegate {
    static let shared = RichWebSnapshotRenderer()

    private var window: UIWindow?
    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, Never>?
    /// Which document the shared view currently hosts. An SVG snapshot replaces the
    /// mermaid host, so the next mermaid render reloads the runtime first.
    private enum HostKind {
        case empty
        case svgDocument
        case mermaidRuntime
    }

    private var hostKind: HostKind = .empty
    /// The pinned runtime, read off main once and kept for the session.
    private var runtimeScript: String?
    private var runtimeLoad: Task<String?, Never>?
    /// The mermaid render generation: a timed-out render's late completion must not
    /// resize or snapshot the view under the next render. Checked after every await.
    private var mermaidGeneration = 0

    /// The wait for `didFinish`; a document that fails or is replaced still resumes it, so a
    /// snapshot request can never hang the queue.
    private func load(_ html: String, in webView: WKWebView, width: CGFloat) async {
        webView.frame = CGRect(x: 0, y: 0, width: width, height: 1)
        window?.frame = CGRect(x: -10_000, y: -10_000, width: width, height: 1)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loadContinuation?.resume()
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    /// Renders `html` at `width` points and returns the image, or nil when there is no scene to
    /// render in (a headless test host) or WebKit refuses the snapshot. `maxHeight` clips the
    /// capture to the card's stage, so a page snapshot is the same picture the live view showed
    /// (a tall page is not squeezed whole into the reserved box); nil captures everything, as a
    /// raw SVG drawing wants.
    func snapshot(html: String, width: CGFloat, scale: CGFloat, maxHeight: CGFloat? = nil) async -> UIImage? {
        guard width > 1, let webView = ensureWebView(width: width) else { return nil }
        await load(html, in: webView, width: width)
        hostKind = .svgDocument
        // One layout pass for the document's own measurement, then size the frame to the content
        // so the snapshot holds the whole drawing (or the card's visible stage).
        try? await Task.sleep(for: .milliseconds(16))
        let content = max(await contentHeight(webView) ?? 1, 1)
        let height = maxHeight.map { min(content, max($0, 1)) } ?? content
        webView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        try? await Task.sleep(for: .milliseconds(16))
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
        // Points: WebKit renders the image at the screen scale itself.
        configuration.snapshotWidth = NSNumber(value: Double(width))
        return try? await webView.takeSnapshot(configuration: configuration)
    }

    // MARK: Mermaid (G4 C9, D2)

    /// Renders one diagram through the shared view: the pinned runtime stays loaded in
    /// its host document, so per diagram there is one `callAsyncJavaScript` and one
    /// snapshot — no 3.5 MB string build, no re-parse, no message-handler plumbing.
    /// A 20 s timeout races the render; a timed-out render's late completion is
    /// discarded by generation and never touches the view under the next render.
    func renderMermaid(source: String, dark: Bool, slotWidth: CGFloat) async -> MermaidRenderOutcome {
        guard slotWidth > 1, let webView = ensureWebView(width: slotWidth) else {
            return .unavailable
        }
        mermaidGeneration += 1
        let generation = mermaidGeneration
        return await withTaskGroup(of: MermaidRenderOutcome.self) { group in
            group.addTask {
                await self.doMermaidRender(
                    source: source, dark: dark, slotWidth: slotWidth, webView: webView,
                    generation: generation)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(Metrics.mermaidRenderTimeout))
                return await self.mermaidTimeout(generation: generation)
            }
            let first = await group.next() ?? .unavailable
            group.cancelAll()
            return first
        }
    }

    /// The timeout's answer. A stale generation answers `.unavailable` at once: it can
    /// only win the race for a render that is already superseded, whose result nobody
    /// shows. (Never park on a continuation that is never resumed — cancelling the group
    /// does not resume it, so the group would wait forever.)
    private func mermaidTimeout(generation: Int) async -> MermaidRenderOutcome {
        guard generation == mermaidGeneration else { return .unavailable }
        return .error(message: "The diagram took too long to render.")
    }

    private func doMermaidRender(
        source: String, dark: Bool, slotWidth: CGFloat, webView: WKWebView, generation: Int
    ) async -> MermaidRenderOutcome {
        guard generation == mermaidGeneration else { return .unavailable }
        guard let script = await runtimeScript() else { return .unavailable }
        guard generation == mermaidGeneration else { return .unavailable }
        if hostKind != .mermaidRuntime {
            await load(hostHTML(script: script), in: webView, width: slotWidth)
            hostKind = .mermaidRuntime
        }
        guard generation == mermaidGeneration else { return .unavailable }
        let theme = dark ? "dark" : "default"
        let result: Any
        do {
            result = try await webView.callAsyncJavaScript(
                "return await window.paseoRender(src, theme)",
                arguments: ["src": source, "theme": theme], in: nil, contentWorld: .page) ?? NSNull()
        } catch {
            // WebKit reports every JavaScript throw as the same sentence ("A JavaScript
            // exception occurred"). The host document catches mermaid's own rejection and
            // returns its message, so a throw here is a harness failure — missing runtime,
            // torn-down view — and the card says no more than that (J1 §2).
            return .unavailable
        }
        guard generation == mermaidGeneration else { return .unavailable }
        guard let dict = result as? [String: Any] else { return .unavailable }
        if let raw = dict["error"] as? String {
            // Mermaid's parse message, reduced to the one line the card can show.
            guard let message = RichMermaidMessage.oneLine(raw) else { return .unavailable }
            return .error(message: message)
        }
        guard let svg = dict["svg"] as? String,
            let width = (dict["width"] as? NSNumber)?.doubleValue,
            let height = (dict["height"] as? NSNumber)?.doubleValue,
            width > 0, height > 0
        else { return .unavailable }
        // Lay the frame out at the natural size, wait two frames (event-driven, not a
        // sleep), then snapshot at screen scale like the SVG path does.
        webView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        _ = try? await webView.evaluateJavaScript(
            "new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))")
        guard generation == mermaidGeneration else { return .unavailable }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
        configuration.snapshotWidth = NSNumber(value: Double(min(width, Metrics.offscreenSnapshotMaxWidth)))
        guard let image = try? await webView.takeSnapshot(configuration: configuration) else {
            return .unavailable
        }
        return .diagram(
            image: image, aspectRatio: width / height, svg: svg)
    }

    /// The pinned runtime, read off main once and kept for the session.
    ///
    /// `Package.swift` builds resources with `.process("Resources")`, which **flattens** folders in
    /// the built bundle — the file ships as `mermaid.min.js`, not `mermaid/mermaid.min.js`. Asking
    /// only for the subdirectory found nothing on device, so every diagram rendered
    /// "Couldn't render diagram" (J1 §2). Both lookups are tried, subdirectory first, the same way
    /// `ClaudeCrabView` finds its sheets.
    private func runtimeScript() async -> String? {
        if let runtimeScript { return runtimeScript }
        if let runtimeLoad { return await runtimeLoad.value }
        let task = Task.detached(priority: .utility) { () -> String? in
            guard let url = Self.mermaidRuntimeURL(),
                let script = try? String(contentsOf: url, encoding: .utf8), !script.isEmpty
            else { return nil }
            return script
        }
        runtimeLoad = task
        let script = await task.value
        runtimeLoad = nil
        if let script {
            runtimeScript = script
        } else {
            // Once per process: the next device run says why instead of just drawing the failure
            // card. `mermaid.min.js` is a local resource, so reading it touches no network.
            Self.runtimeLog.error("mermaid.min.js is not in the built bundle; diagrams cannot render")
        }
        return script
    }

    private static let runtimeLog = Logger(
        subsystem: "com.wiselfx.paseoclient", category: "mermaid")

    /// The flattened name first, then the folder name a differently built bundle would keep.
    nonisolated private static func mermaidRuntimeURL() -> URL? {
        Bundle.module.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "mermaid")
            ?? Bundle.module.url(forResource: "mermaid.min", withExtension: "js")
    }

    /// The single host document: the runtime inline once, then one
    /// `window.paseoRender(src, theme)` call per diagram. Re-initializing mermaid per
    /// call picks up scheme changes without reloading the runtime.
    private func hostHTML(script: String) -> String {
        """
        <!DOCTYPE html><html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        <style>html,body{margin:0;padding:0;background:transparent}</style>
        <script>\(script)</script>
        <script>function paseoErrorText(e){try{if(typeof e==='string')return e;var m=e&&(e.message||e.str);return(m===undefined||m===null)?'':String(m);}catch(x){return '';}}
        window.paseoRender=function(src,theme){function fail(e){return Promise.resolve({error:paseoErrorText(e)});}try{mermaid.initialize({startOnLoad:false,securityLevel:'strict',suppressErrorRendering:true,theme:theme,flowchart:{htmlLabels:false}});return mermaid.render('paseo-diagram',src).then(function(r){document.getElementById('stage').innerHTML=r.svg;var svg=document.querySelector('#stage svg');var w=0,h=0;try{var vb=svg.viewBox.baseVal;if(vb&&vb.width>0&&vb.height>0){w=vb.width;h=vb.height;}}catch(e){}if(!(w>0&&h>0)){var b=svg.getBoundingClientRect();w=b.width;h=b.height;}svg.style.maxWidth='none';svg.style.width=w+'px';svg.style.height=h+'px';svg.setAttribute('width',w);svg.setAttribute('height',h);return{svg:r.svg,width:w,height:h};},fail);}catch(e){return fail(e);}};</script>
        </head><body><div id="stage"></div></body></html>
        """
    }

    private func contentHeight(_ webView: WKWebView) async -> CGFloat? {
        let script =
            "Math.max(document.documentElement.scrollHeight || 0, document.body.scrollHeight || 0)"
        let value = try? await webView.evaluateJavaScript(script)
        guard let number = value as? NSNumber else { return nil }
        return CGFloat(number.doubleValue)
    }

    /// Starts the shared web view's process before a card needs it (W1). The first diagram or SVG
    /// snapshot built the view on the main thread in the middle of a scroll and waited for WebKit's
    /// content process to launch: a 605 to 726 ms stall (`WKWebView.init` blocked in `__ulock_wait2`,
    /// sampled). Called once when a conversation opens, so the cost lands where the chat is already
    /// busy opening, not under the reader's finger.
    func prewarm() {
        _ = ensureWebView(width: 390)
    }

    private func ensureWebView(width: CGFloat) -> WKWebView? {
        if let webView { return webView }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        else { return nil }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // On for mermaid; the SVG documents' CSP still blocks their scripts, and the
        // artifact pages add the compiled content rules on top.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        Task {
            // Defense in depth on the shared view, applied when the first compile
            // lands; every document here already carries an offline CSP.
            if let rules = await OfflineContentRules.list() {
                configuration.userContentController.add(rules)
            }
        }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 1), configuration: configuration)
        view.navigationDelegate = self
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.backgroundColor = .clear
        view.isInspectable = false
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -10_000, y: -10_000, width: width, height: 1)
        window.windowLevel = .normal - 1
        window.backgroundColor = .clear
        window.addSubview(view)
        window.isHidden = false
        self.window = window
        self.webView = view
        return view
    }

    private func finishLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad()
    }

    func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        finishLoad()
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finishLoad()
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
#endif
