#if canImport(UIKit)
import SwiftUI
import UIKit
import WebKit

/// One shared, offscreen `WKWebView` that renders SVG to an image (R9 §2).
///
/// SVG blocks used to mount a live `WKWebView` each. A static drawing does not need one: it is
/// rendered once at display width, cached by content, and drawn as an image. The viewer's sheet
/// still gets the live view for zooming.
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

/// How many live `WKWebView`s the transcript may hold (R9 §2). Two cards scrolling into view at
/// once is the most a reader can look at; the rest draw their snapshot.
@MainActor
final class LiveWebViewBudget {
    static let shared = LiveWebViewBudget()
    private(set) var live = 0
    private let limit = 2

    /// True when a slot was taken; the caller must `release()` it.
    func claim() -> Bool {
        guard live < limit else { return false }
        live += 1
        return true
    }

    func release() {
        live = max(0, live - 1)
    }
}

/// A raw `<svg>` block: a snapshot of the drawing, cached by content, with the live document in a
/// sheet for zooming (R9 §2). Tap opens the sheet; "View source" swaps in the markup.
struct RichSVGCard: View {
    let code: String

    @State private var image: UIImage?
    @State private var showSource = false
    @State private var showLive = false
    @State private var width: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    private var dark: Bool { colorScheme == .dark }

    /// Built once per (content, scheme): the document is a string, not a `body` computation.
    private var document: String { RichHTMLDocument.rawSVG(source: code, dark: dark) }

    var body: some View {
        RichCard {
            VStack(alignment: .leading, spacing: 10) {
                header
                if showSource {
                    source
                } else {
                    drawing
                }
            }
        }
        .background { widthReader }
        .task(id: renderKey) { await render() }
        .sheet(isPresented: $showLive) {
            SheetScaffold("SVG", detents: .large) {
                SandboxedHTMLView(
                    html: document, heightFloor: 1, heightCeiling: 20_000,
                    onHeightChange: { _ in }, fillsFrame: true)
                    .ignoresSafeArea(edges: .bottom)
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
                .frame(maxWidth: .infinity, maxHeight: 480)
                .contentShape(.rect)
                .onTapGesture { showLive = true }
                .accessibilityLabel("SVG drawing, tap to open")
        } else {
            Rectangle()
                .fill(Palette.codeSurface)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .overlay { ProgressView().controlSize(.small).tint(Palette.secondaryInk) }
        }
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
            html: document, width: width, scale: UIScreen.main.scale)
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
                    Haptics.selection()
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
#endif
