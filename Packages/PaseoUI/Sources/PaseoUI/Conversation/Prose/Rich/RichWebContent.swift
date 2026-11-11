#if canImport(UIKit)
import SwiftUI
import UIKit
import WebKit

/// One shared, offscreen `WKWebView` that renders SVG to an image (R9 §2).
///
/// SVG blocks used to mount a live `WKWebView` each. A static drawing does not need one: it is
/// rendered once at display width, cached by content, and drawn as an image; the full-screen
/// viewer zooms that image (E3 §3.1). Rasterising beats a live view because the result is a
/// plain `UIImage`: no web process per card, no per-scroll work, and crisp at
/// `displayScale` because WebKit snapshots at the screen scale.
///
/// The web view lives in a 1 pt window parked off screen — `takeSnapshot(with:)` only renders
/// views that are in a window hierarchy. JavaScript is off and the document's CSP allows no
/// network, so nothing here can run or fetch.
@MainActor
final class RichWebSnapshotRenderer: NSObject, WKNavigationDelegate {
    static let shared = RichWebSnapshotRenderer()

    private var window: UIWindow?
    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, Never>?

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
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
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

/// Serializes snapshot requests: one offscreen render at a time, in the order they were asked for.
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
