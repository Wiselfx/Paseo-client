#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit
import WebKit

// MARK: - ArtifactDocument (G4 C9, G5 C8)

// NOTE: RemoteImagePipeline/G4: G4 ships the mermaid kind; G5 adds visualize/svg/html
// and grows this page (title extraction, Reload, Share as .html, Preview entries).
// NOTE: RemoteImagePipeline/G5: no viz bridges (`sendPrompt`/`saveState`/`loadState`)
// on this page — they do not exist in the inline card either (verified by grep:
// `SandboxedHTMLView` carries only the height reporter, and the reference's bridge
// protocol was never ported). The page hosts the identical document, so bridges land
// in both places at once when they are built (with the composer steer path).

/// One full-screen artifact: values only (R-2). The card builds it; the controller
/// presents it; the viewer never refetches. Identity equality only: the bitmap is
/// payload, not identity (like `MediaViewerItem`).
struct ArtifactDocument: Identifiable, Equatable, @unchecked Sendable {
    static func == (lhs: ArtifactDocument, rhs: ArtifactDocument) -> Bool {
        lhs.id == rhs.id
    }

    enum Kind: Equatable, Sendable {
        /// A rendered diagram: the live vector SVG plus the snapshot for Share.
        case mermaid(source: String, svg: String?, snapshot: UIImage?)
        /// A ` ```visualize ` fence: the self-contained interactive stage.
        case visualize(code: String)
        /// A raw `<svg>` block.
        case svg(source: String)
        /// An html fence, or a `.html` file: a full document when the source carries
        /// `<html>`, otherwise a fragment wrapped in the offline shell on load.
        case html(source: String, fileName: String?)
    }

    var kind: Kind
    /// The image the card already drew, for Share when the kind has one.
    var shareImage: UIImage?

    var id: String {
        switch kind {
        case .mermaid(let source, _, _): "mermaid:\(source.hashValue)"
        case .visualize(let code): "visualize:\(code.hashValue)"
        case .svg(let source): "svg:\(source.hashValue)"
        case .html(let source, let fileName):
            "html:\(fileName ?? ""):\(source.hashValue)"
        }
    }

    /// The page title: the document's own `<title>`/`<h1>` for HTML, upstream's
    /// wording where it exists (`en.ts:325`), the existing card copy otherwise.
    var title: String {
        switch kind {
        case .mermaid: "Diagram"
        case .visualize: "Visualization"
        case .svg: "SVG"
        case .html(let source, let fileName):
            ArtifactTitle.extract(html: source) ?? fileName ?? "HTML"
        }
    }

    /// The live document the page hosts, in the app's scheme.
    func liveHTML(dark: Bool) -> String? {
        switch kind {
        case .mermaid(_, let svg, _):
            // Static SVG: scripts never run (the CSP has no `script-src`).
            guard let svg else { return nil }
            return RichHTMLDocument.artifactSVG(source: svg, dark: dark)
        case .visualize(let code):
            return RichHTMLDocument.visualize(code: code, dark: dark)
        case .svg(let source):
            return RichHTMLDocument.rawSVG(source: source, dark: dark)
        case .html(let source, _):
            return RichHTMLDocument.artifactHTML(source: source, dark: dark)
        }
    }

    /// The source the toggle shows.
    var sourceText: String {
        switch kind {
        case .mermaid(let source, _, _): source
        case .visualize(let code): code
        case .svg(let source): source
        case .html(let source, _): source
        }
    }

    /// Whether the document re-runs on Reload (scripted stages do; static SVG doesn't).
    var canReload: Bool {
        switch kind {
        case .mermaid, .svg: false
        case .visualize, .html: true
        }
    }

    /// The exported file name: the title slugged, always `.html` (the export must open
    /// correctly in Safari in both schemes, so the scheme is baked in at export time).
    var shareFileName: String {
        let slug = title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined().split(separator: "-").joined(separator: "-")
        return (slug.isEmpty ? "artifact" : String(slug.prefix(48))) + ".html"
    }
}
/// The shared zoom namespace for artifact opens (G4 §1.2): the card's thumbnail and the
/// controller-presented page live in different hierarchies, so `ChatSheets` owns one
/// namespace and lends it down through the environment.
private struct ArtifactZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var artifactZoomNamespace: Namespace.ID? {
        get { self[ArtifactZoomNamespaceKey.self] }
        set { self[ArtifactZoomNamespaceKey.self] = newValue }
    }
}

/// Applies the zoom source only when the shared namespace is present (previews have
/// none, and degrade to the default cover transition).
struct ArtifactZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - ArtifactPage (G4 C9, G5 C8)

// NOTE: RemoteImagePipeline/G4: v1 hosts the live diagram with source toggle and Share.
// G5 adds title extraction, Reload, bridges, Share as .html, Preview entries and the
// Files-panel destination. The page leases one `WebViewSlotPool` slot while open, which
// outranks transcript slots (cards fall back to snapshots via `artifactPageOpen`).

/// The full-screen home for an artifact (G4: the live diagram). A SwiftUI page over one
/// pooled `WKWebView`: pinch-zoom stays sharp because the content is vector, not the
/// transcript snapshot.
struct ArtifactPage: View {
    let document: ArtifactDocument
    let sourceID: String
    let namespace: Namespace.ID
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.richActions) private var richActions
    @State private var showSource = false
    @State private var shareImage: UIImage?
    @State private var shareFileURL: URL?
    @State private var safariURL: URL?
    @State private var reloadToken = 0
    @State private var holdsSlot = false

    private var dark: Bool { colorScheme == .dark }

    /// The loaded document: the live build plus the reload token, which forces
    /// `SandboxedHTMLView` to reload (its `loadedHTML` compare drives the load).
    private var liveDocument: String? {
        guard var base = document.liveHTML(dark: dark) else { return nil }
        if reloadToken > 0 { base += "\n<!--reload:\(reloadToken)-->" }
        return base
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if showSource {
                sourceView
            } else if let html = liveDocument, holdsSlot {
                SandboxedHTMLView(
                    html: html, heightFloor: 0, heightCeiling: .greatestFiniteMagnitude,
                    onHeightChange: { _ in }, fillsFrame: true,
                    allowsScripts: allowsScripts,
                    onExternalNavigation: previewFiles == nil ? nil : { safariURL = $0 },
                    previewFiles: previewFiles)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let fallback = document.shareImage {
                Image(uiImage: fallback)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().controlSize(.small).tint(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .modifier(MediaViewerTransition(
            sourceID: sourceID, namespace: namespace, reduceMotion: reduceMotion))
        .accessibilityAction(.escape) { onClose() }
        .onAppear { claimSlot() }
        .onDisappear { releaseSlot() }
        .sheet(isPresented: Binding(get: { shareImage != nil }, set: { if !$0 { shareImage = nil } })) {
            if let shareImage {
                ActivityView(items: [shareImage])
            }
        }
        .sheet(isPresented: Binding(get: { shareFileURL != nil }, set: { if !$0 { shareFileURL = nil } })) {
            if let shareFileURL {
                ActivityView(items: [shareFileURL])
            }
        }
        .sheet(isPresented: Binding(get: { safariURL != nil }, set: { if !$0 { safariURL = nil } })) {
            if let safariURL {
                SafariView(url: safariURL).ignoresSafeArea()
            }
        }
    }

    /// Chat artifacts stay offline (CSP `connect-src 'none'`); file previews may load
    /// CDN subresources through the scheme handler, like the Files panel does.
    private var allowsScripts: Bool {
        switch document.kind {
        case .mermaid, .svg: false
        case .visualize, .html: true
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.paseo(.body))
                    .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                    .contentShape(.circle)
            }
            .glassEffect(in: .circle)
            .accessibilityLabel("Close viewer")
            Spacer(minLength: 8)
            Text(document.title)
                .font(.paseo(.headline))
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Button(showSource ? "View diagram" : "View source") {
                    showSource.toggle()
                }
                Button("Copy source", systemImage: "doc.on.doc") {
                    if let richActions {
                        richActions.copyText(document.sourceText)
                    } else {
                        UIPasteboard.general.string = document.sourceText
                        Haptics.light()
                    }
                }
                if document.canReload {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        reloadToken += 1
                    }
                }
                if document.shareImage != nil {
                    Button("Share image", systemImage: "square.and.arrow.up") {
                        shareImage = document.shareImage
                    }
                } else {
                    Button("Share as .html", systemImage: "square.and.arrow.up") {
                        shareHTMLFile()
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.paseo(.body))
                    .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                    .contentShape(.circle)
            }
            .glassEffect(in: .circle)
            .accessibilityLabel("Artifact actions")
        }
        .padding(.horizontal, Space.md)
        .padding(.top, Space.md)
    }

    private var sourceView: some View {
        ScrollView {
            Text(document.sourceText)
                .font(.paseo(.codeSmall))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.md)
        }
    }

    /// One pooled slot while open; without one the page shows the card's snapshot
    /// instead of a third live view (§0: at most 2 live WKWebViews).
    /// The exported `.html`: the live document in the current scheme, written off main.
    /// The menu offers it per kind; mermaid keeps Share image instead.
    private func shareHTMLFile() {
        let fileName = document.shareFileName
        let dark = dark
        Task { @MainActor in
            let url = await Task.detached(priority: .userInitiated) { () -> URL? in
                guard let directory = FileManager.default.urls(
                    for: .cachesDirectory, in: .userDomainMask
                ).first?.appending(path: "artifacts", directoryHint: .isDirectory),
                let html = ArtifactDocument(kind: document.kind, shareImage: nil)
                    .liveHTML(dark: dark),
                let data = html.data(using: .utf8)
                else { return nil }
                try? FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                let url = directory.appending(path: fileName, directoryHint: .notDirectory)
                guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
                return url
            }.value
            shareFileURL = url
        }
    }

    private func claimSlot() {
        if !holdsSlot { holdsSlot = WebViewSlotPool.shared.claim() }
    }

    private func releaseSlot() {
        if holdsSlot {
            holdsSlot = false
            WebViewSlotPool.shared.release()
        }
    }
}
#endif
