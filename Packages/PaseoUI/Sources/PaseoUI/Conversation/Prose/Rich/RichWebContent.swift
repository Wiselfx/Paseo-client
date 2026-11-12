#if canImport(UIKit)
import OSLog
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
    /// render in (a headless test host) or WebKit refuses the snapshot.
    func snapshot(html: String, width: CGFloat, scale: CGFloat) async -> UIImage? {
        guard width > 1, let webView = ensureWebView(width: width) else { return nil }
        await load(html, in: webView, width: width)
        hostKind = .svgDocument
        // One layout pass for the document's own measurement, then size the frame to the content
        // so the snapshot holds the whole drawing.
        try? await Task.sleep(for: .milliseconds(16))
        let height = max(await contentHeight(webView) ?? 1, 1)
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
                arguments: ["src": source, "theme": theme], in: nil, contentWorld: .page)
        } catch {
            return .error(message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        guard generation == mermaidGeneration else { return .unavailable }
        guard let dict = result as? [String: Any],
            let svg = dict["svg"] as? String,
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
    private static func mermaidRuntimeURL() -> URL? {
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
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        <style>html,body{margin:0;padding:0;background:transparent}</style>
        <script>\(script)</script>
        <script>window.paseoRender=function(src,theme){mermaid.initialize({startOnLoad:false,securityLevel:'strict',suppressErrorRendering:true,theme:theme,flowchart:{htmlLabels:false}});return mermaid.render('paseo-diagram',src).then(function(r){document.getElementById('stage').innerHTML=r.svg;var svg=document.querySelector('#stage svg');var w=0,h=0;try{var vb=svg.viewBox.baseVal;if(vb&&vb.width>0&&vb.height>0){w=vb.width;h=vb.height;}}catch(e){}if(!(w>0&&h>0)){var b=svg.getBoundingClientRect();w=b.width;h=b.height;}return{svg:r.svg,width:w,height:h};});};</script>
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

/// Serializes offscreen renders: one at a time, in the order asked for — SVG snapshots
/// and mermaid renders share the tail because they share the one offscreen view.
/// It is main-actor rather than an `actor` because its resource (`WKWebView`) is main-actor bound;
/// the queueing guarantee is the same.
@MainActor
final class RichSnapshotQueue {
    static let shared = RichSnapshotQueue()
    private var tail: Task<Void, Never>?

    func snapshot(html: String, width: CGFloat, scale: CGFloat) async -> UIImage? {
        let previous = tail
        let result: UIImage? = await withCheckedContinuation { continuation in
            let task = Task { @MainActor in
                _ = await previous?.value
                let image = await RichWebSnapshotRenderer.shared.snapshot(
                    html: html, width: width, scale: scale)
                continuation.resume(returning: image)
            }
            tail = task
        }
        return result
    }

    func mermaid(source: String, dark: Bool, slotWidth: CGFloat) async -> MermaidRenderOutcome {
        let previous = tail
        let result: MermaidRenderOutcome = await withCheckedContinuation { continuation in
            let task = Task { @MainActor in
                _ = await previous?.value
                let outcome = await RichWebSnapshotRenderer.shared.renderMermaid(
                    source: source, dark: dark, slotWidth: slotWidth)
                continuation.resume(returning: outcome)
            }
            tail = task
        }
        return result
    }
}

/// Snapshots of rich content, by content and layout. `NSCache` drops them under memory pressure.
@MainActor
enum RichSnapshotCache {
    private static let table: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        cache.totalCostLimit = 24_000_000
        return cache
    }()

    static func image(for key: String) -> UIImage? {
        table.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        table.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Content identity, not the string: the hash keeps the key small for a 100 KB drawing.
    static func key(html: String, width: CGFloat, dark: Bool) -> String {
        "\(html.hashValue)/\(Int(width.rounded()))/\(dark ? "d" : "l")"
    }
}

/// How many live `WKWebView`s the app may hold (§0: at most 2). Two cards scrolling into
/// view at once is the most a reader can look at; the rest draw their snapshot. The
/// artifact page leases one slot while open, which outranks transcript slots (G4/G5):
/// transcript web cards release theirs and fall back to snapshots.
@MainActor
final class WebViewSlotPool {
    static let shared = WebViewSlotPool()
    private(set) var live = 0
    private let limit = 2

    /// True when a slot was taken; the caller must `release()` it.
    func claim() -> Bool {
        guard live < limit else { return false }
        live += 1
        debugLog()
        return true
    }

    func release() {
        live = max(0, live - 1)
        debugLog()
    }

    /// The DEBUG counter that proves the §0 budget: every claim and release logs the
    /// live count, so a 20-card scroll can be audited without Instruments.
    private func debugLog() {
        #if DEBUG
        print("[webview-slots] live=\(live)/\(limit)")
        #endif
    }
}

/// A raw `<svg>` block (E3 §3.1): a snapshot of the drawing at the transcript width, its
/// intrinsic aspect ratio reserved before the render lands, capped at 60 % of the screen height,
/// and a full-screen pinch-zoom viewer on tap. No inner scrolling, no live web view per card.
struct RichSVGCard: View {
    let code: String

    @State private var image: UIImage?
    @State private var showSource = false
    @State private var showViewer = false
    @State private var width: CGFloat = 0
    @Namespace private var zoom
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private var dark: Bool { colorScheme == .dark }

    /// Built once per (content, scheme): the document is a string, not a `body` computation.
    private var document: String { RichHTMLDocument.rawSVG(source: code, dark: dark) }

    /// From `viewBox`, else `width`/`height`; nil when the drawing carries neither.
    private var intrinsicAspectRatio: CGFloat? { RichSVGIntrinsic.aspectRatio(of: code) }

    /// The container's height, for the 60 % cap, known before the first frame (`RichViewport`).
    @Environment(\.richViewportHeight) private var viewportHeight

    /// A tall drawing shrinks to fit instead of pushing the turn away.
    private var heightCap: CGFloat { viewportHeight * 0.6 }

    var body: some View {
        PaseoCard(content:
            VStack(alignment: .leading, spacing: 10) {
                header
                if showSource {
                    source
                } else {
                    drawing
                }
            })
        .background { widthReader }
        .task(id: renderKey) { await render() }
        .fullScreenCover(isPresented: $showViewer) {
            if let image {
                MediaViewerView(
                    items: [
                        MediaViewerItem(
                            id: "svg:\(code.hashValue)",
                            thumbnail: image,
                            fullSource: nil,
                            fileName: "drawing.svg",
                            alt: "SVG drawing",
                            filePath: nil)
                    ],
                    sourceID: "svg:\(code.hashValue)",
                    namespace: zoom,
                    onClose: { showViewer = false },
                    selection: .constant(0))
            }
        }
    }

    private var header: some View {
        HStack {
            Text("SVG")
                .font(ProseFonts.sans(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button {
                showSource.toggle()
            } label: {
                Text(showSource ? "Hide source" : "View source")
                    .font(ProseFonts.mono(size: 11))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .overlay(Capsule().strokeBorder(Palette.cardBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showSource ? "Hide source" : "View source")
        }
    }

    @ViewBuilder private var drawing: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: heightCap)
                .contentShape(.rect)
                .matchedTransitionSource(id: "svg:\(code.hashValue)", in: zoom)
                .onTapGesture {
                    showViewer = true
                }
                .accessibilityLabel("SVG drawing, tap to open")
                .accessibilityAddTraits(.isButton)
        } else {
            Rectangle()
                .fill(Palette.codeSurface)
                .frame(maxWidth: .infinity)
                .frame(height: placeholderHeight)
                .overlay { ProgressView().controlSize(.small).tint(Palette.secondaryInk) }
        }
    }

    /// The size the drawing will take, from its own ratio, so the card does not jump when the
    /// snapshot arrives. Falls back to the old 120 pt strip for a drawing with no size hints.
    private var placeholderHeight: CGFloat {
        guard let ratio = intrinsicAspectRatio else { return min(120, heightCap) }
        // Before layout the width is unknown; assume a phone-width card.
        let assumedWidth = width > 1 ? width : 350
        return min(assumedWidth / ratio, heightCap)
    }

    /// The card's inner width, for rendering the drawing at its real size instead of a guess.
    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
        }
    }

    /// Nil until the width is known: a render at a guessed width would only be thrown away.
    private var renderKey: String? {
        guard width > 1 else { return nil }
        return RichSnapshotCache.key(html: document, width: width, dark: dark)
    }

    @MainActor
    private func render() async {
        guard let key = renderKey else { return }
        if let cached = RichSnapshotCache.image(for: key) {
            image = cached
            return
        }
        let rendered = await RichSnapshotQueue.shared.snapshot(
            html: document, width: width, scale: displayScale)
        guard let rendered else { return }
        RichSnapshotCache.store(rendered, for: key)
        image = rendered
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(code)
                    .font(ProseFonts.mono(size: 11))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            HStack {
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = code
                    Haptics.light()
                } label: {
                    Label("Copy source", systemImage: "doc.on.doc")
                        .font(ProseFonts.sans(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The `<svg>` element's intrinsic aspect ratio: `viewBox` first (the drawing's real geometry),
/// then `width`/`height` attributes in px. Percentages are ignored — they say nothing about the
/// drawing itself. Used to reserve the card's height before the snapshot lands.
enum RichSVGIntrinsic {
    static func aspectRatio(of source: String) -> CGFloat? {
        guard let open = source.range(of: "<svg", options: .caseInsensitive),
            let tagEnd = source.range(of: ">", range: open.upperBound..<source.endIndex)
        else { return nil }
        let tag = source[open.upperBound..<tagEnd.lowerBound]

        if let viewBox = attribute("viewBox", in: tag) {
            let parts = viewBox.split { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n" }
                .compactMap { Double($0) }
            if parts.count == 4, parts[2] > 0, parts[3] > 0 {
                return CGFloat(parts[2] / parts[3])
            }
        }
        if let width = length(attribute("width", in: tag)),
            let height = length(attribute("height", in: tag)), height > 0
        {
            return width / height
        }
        return nil
    }

    /// `"400"` or `"400px"` → 400; `"100%"` → nil.
    private static func length(_ value: String?) -> CGFloat? {
        guard let value else { return nil }
        let digits = value.prefix { $0.isNumber || $0 == "." }
        guard digits.count == value.trimmingCharacters(in: .whitespaces).count
            || value.hasSuffix("px"),
            let number = Double(digits), number > 0
        else { return nil }
        return CGFloat(number)
    }

    private static func attribute(_ name: String, in tag: Substring) -> String? {
        // Attribute order is free and quoting may be single or double.
        var search = tag.startIndex..<tag.endIndex
        while let hit = tag.range(of: name, options: .caseInsensitive, range: search) {
            // The name must start an attribute, not sit inside one (`stroke-width`, a value).
            let startsAttribute = hit.lowerBound == tag.startIndex
                || tag[tag.index(before: hit.lowerBound)].isWhitespace
            guard startsAttribute else {
                search = hit.upperBound..<tag.endIndex
                continue
            }
            var cursor = hit.upperBound
            while cursor < tag.endIndex, tag[cursor] == " " { cursor = tag.index(after: cursor) }
            guard cursor < tag.endIndex, tag[cursor] == "=" else {
                search = hit.upperBound..<tag.endIndex
                continue
            }
            cursor = tag.index(after: cursor)
            while cursor < tag.endIndex, tag[cursor] == " " { cursor = tag.index(after: cursor) }
            guard cursor < tag.endIndex, tag[cursor] == "\"" || tag[cursor] == "'" else {
                return nil
            }
            let quote = tag[cursor]
            let valueStart = tag.index(after: cursor)
            guard let valueEnd = tag[valueStart...].firstIndex(of: quote) else { return nil }
            return String(tag[valueStart..<valueEnd])
        }
        return nil
    }
}
#endif
