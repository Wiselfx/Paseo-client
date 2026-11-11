#if canImport(UIKit)
import SwiftUI
import UIKit
import WebKit

// MARK: - ArtifactDocument (G4 C9, G5 C8)

// NOTE: RemoteImagePipeline/G4: G4 ships the mermaid kind; G5 adds visualize/svg/html
// and grows this page (title extraction, Reload, Share as .html, Preview entries).

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
    }

    var kind: Kind
    /// The image the card already drew, for Share when the kind has one.
    var shareImage: UIImage?

    var id: String {
        switch kind {
        case .mermaid(let source, _, _): "mermaid:\(source.hashValue)"
        }
    }

    /// The page title. Upstream's wording where it exists (`en.ts:325`).
    var title: String {
        switch kind {
        case .mermaid: "Diagram"
        }
    }

    /// The live document the page hosts. Static SVG: scripts never run (the CSP has no
    /// `script-src`), so the diagram cannot reach the network or the app.
    /// The live document the page hosts, in the app's scheme. Static SVG: scripts never
    /// run (the CSP has no `script-src`), so the diagram cannot reach the network or the app.
    func liveHTML(dark: Bool) -> String? {
        switch kind {
        case .mermaid(_, let svg, _):
            guard let svg else { return nil }
            return RichHTMLDocument.artifactSVG(source: svg, dark: dark)
        }
    }

    /// The source the toggle shows.
    var sourceText: String {
        switch kind {
        case .mermaid(let source, _, _): source
        }
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
    @State private var showSource = false
    @State private var shareImage: UIImage?
    @State private var holdsSlot = false

    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if showSource {
                sourceView
            } else if let html = document.liveHTML(dark: dark), holdsSlot {
                SandboxedHTMLView(
                    html: html, heightFloor: 0, heightCeiling: .greatestFiniteMagnitude,
                    onHeightChange: { _ in }, fillsFrame: true)
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
                    UIPasteboard.general.string = document.sourceText
                    Haptics.light()
                }
                if document.shareImage != nil {
                    Button("Share image", systemImage: "square.and.arrow.up") {
                        shareImage = document.shareImage
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
