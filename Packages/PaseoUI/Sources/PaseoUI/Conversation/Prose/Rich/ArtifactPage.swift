#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// The shared zoom namespace for artifact opens (G4 §1.2): the card's thumbnail and the
/// controller-presented page live in different hierarchies, so `ChatSheets` owns one
/// namespace and lends it down through the environment.
extension EnvironmentValues {
    @Entry var artifactZoomNamespace: Namespace.ID?
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
    /// File previews read workspace files through this; nil for chat artifacts, which
    /// never leave their offline sandbox.
    var previewFiles: PreviewFileSource? = nil
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
    /// The compiled offline rules for chat documents; file previews skip them and keep
    /// the Files panel's CDN access.
    @State private var contentRules: WKContentRuleList?

    private var dark: Bool { colorScheme == .dark }

    /// File previews render without the rule list; chat documents wait for it.
    private var contentRulesReady: Bool { previewFiles != nil || contentRules != nil }

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
            } else if let html = liveDocument, holdsSlot, contentRulesReady {
                SandboxedHTMLView(
                    html: html, heightFloor: 0, heightCeiling: .greatestFiniteMagnitude,
                    onHeightChange: { _ in }, fillsFrame: true,
                    allowsScripts: allowsScripts,
                    onExternalNavigation: previewFiles == nil ? nil : { safariURL = $0 },
                    previewFiles: previewFiles,
                    contentRuleList: contentRules,
                    awaitContentRules: previewFiles == nil)
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
        .toolbarVisibility(.hidden, for: .navigationBar)
        .modifier(MediaViewerTransition(
            sourceID: sourceID, namespace: namespace, reduceMotion: reduceMotion))
        .accessibilityAction(.escape) { onClose() }
        .task {
            if previewFiles == nil {
                contentRules = await OfflineContentRules.list()
            }
        }
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
                Button(showSource ? sourceToggleHideTitle : "View source") {
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

    /// The toggle-back title: upstream's "View diagram" for mermaid; the page for the
    /// rest, matching the cards ("View source" there toggles back to the content).
    private var sourceToggleHideTitle: String {
        switch document.kind {
        case .mermaid: "View diagram"
        default: "View page"
        }
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
