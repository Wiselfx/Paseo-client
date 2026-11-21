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
    @State private var sheet: ArtifactPageSheet?
    @State private var reloadToken = 0
    /// Bumped on a pasteboard copy (no `RichActions`): the copy haptic, once per tap.
    @State private var copyTaps = 0
    /// The live document and the title, built once per scheme/reload (`rebuildDocument`), never
    /// in `body`: building an HTML artifact lowercases and scans its whole source, and body
    /// re-runs on every state flip.
    @State private var liveHTML: String?
    @State private var title = ""
    @State private var holdsSlot = false
    /// The compiled offline rules for chat documents; file previews skip them and keep
    /// the Files panel's CDN access.
    @State private var contentRules: WKContentRuleList?

    private var dark: Bool { colorScheme == .dark }

    /// File previews render without the rule list; chat documents wait for it.
    private var contentRulesReady: Bool { previewFiles != nil || contentRules != nil }

    var body: some View {
        VStack(spacing: 0) {
            ArtifactPageTopBar(
                title: title,
                hideSourceTitle: sourceToggleHideTitle,
                canReload: document.canReload,
                hasShareImage: document.shareImage != nil,
                showSource: $showSource,
                onClose: onClose,
                onCopy: copySource,
                onReload: reload,
                onShare: share)
            if showSource {
                sourceView
            } else if let html = liveHTML, holdsSlot, contentRulesReady {
                SandboxedHTMLView(
                    html: html, heightFloor: 0, heightCeiling: .greatestFiniteMagnitude,
                    onHeightChange: { _ in }, fillsFrame: true,
                    allowsScripts: allowsScripts,
                    onExternalNavigation: previewFiles == nil ? nil : { sheet = .safari($0) },
                    previewFiles: previewFiles,
                    contentRuleList: contentRules,
                    awaitContentRules: previewFiles == nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let fallback = document.shareImage {
                Image(uiImage: fallback)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(title)
            } else {
                ProgressView().controlSize(.small).tint(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.background)
        .paseoFeedback(.light, trigger: copyTaps)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .modifier(MediaViewerTransition(
            sourceID: sourceID, namespace: namespace, reduceMotion: reduceMotion))
        .accessibilityAction(.escape) { onClose() }
        .task {
            if previewFiles == nil {
                contentRules = await OfflineContentRules.list()
            }
        }
        .task(id: "\(dark)|\(reloadToken)") { rebuildDocument() }
        .onAppear { claimSlot() }
        .onDisappear { releaseSlot() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .shareImage(let image): ActivityView(items: [image])
            case .shareFile(let url): ActivityView(items: [url])
            case .safari(let url): SafariView(url: url).ignoresSafeArea()
            }
        }
    }

    /// The loaded document: the live build plus the reload token, which forces
    /// `SandboxedHTMLView` to reload (its `loadedHTML` compare drives the load). Runs when the
    /// scheme or the token changes; the first frame already waits on the slot and the rules.
    private func rebuildDocument() {
        title = document.title
        guard var base = document.liveHTML(dark: dark) else {
            liveHTML = nil
            return
        }
        if reloadToken > 0 { base += "\n<!--reload:\(reloadToken)-->" }
        liveHTML = base
    }

    private func copySource() {
        if let richActions {
            richActions.copyText(document.sourceText)
        } else {
            UIPasteboard.general.string = document.sourceText
            copyTaps += 1
        }
    }

    private func reload() {
        reloadToken += 1
    }

    private func share() {
        if let image = document.shareImage {
            sheet = .shareImage(image)
        } else {
            shareHTMLFile()
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

    /// The exported `.html`: the live document in the current scheme, written off main.
    /// The menu offers it per kind; mermaid keeps Share image instead.
    private func shareHTMLFile() {
        let kind = document.kind
        let fileName = document.shareFileName
        let dark = dark
        Task { @MainActor in
            if let url = await ArtifactShareFile.write(kind: kind, dark: dark, fileName: fileName) {
                sheet = .shareFile(url)
            }
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
