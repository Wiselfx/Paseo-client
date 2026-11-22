#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// A ` ```visualize ` or ` ```html ` block: a sandboxed WKWebView sized to its content, with a
/// "View source" toggle that swaps in the raw source with a copy button.
///
/// E3 §3.2: the height follows the reported content up to 70 % of the window height. V2: the
/// page is measured once, after its load, then fixed — a later layout change never re-flows
/// the transcript. Past the cap an "Open" button shows the page full screen.
///
/// The live web view exists only on a first on-screen visit, with a slot and the compiled
/// offline rules (R9 §2, at most 2 live). Off screen the card snapshots itself and releases
/// its slot; a later visit draws that snapshot on its first frame, so nothing flashes.
/// Interaction has its home on the artifact page (G5 C8).
struct RichWebCard: View {
    let code: String
    let kind: RichWebCardKind
    /// `code.hashValue` once per value, not once per `body` read: every cache key and the
    /// viewer identity use it.
    private let contentKey: String

    init(code: String, kind: RichWebCardKind) {
        self.code = code
        self.kind = kind
        self.contentKey = "\(kind.contentKey):\(code.hashValue)"
    }

    @State private var showSource = false
    @State private var contentHeight: CGFloat = WebCardMetrics.reservedHeight
    /// True once the page published its load-time height: the one and only reflow.
    @State private var measuredHeight = false
    @State private var overflows = false
    @State private var isVisible = false
    @State private var holdsSlot = false
    @State private var snapshot: UIImage?
    /// A page from an earlier visit is cached: draw it, never mount a fresh blank view.
    @State private var prefersSnapshot = false
    /// The snapshot path ended without an image (no scene, WebKit refused): say so instead
    /// of spinning forever.
    @State private var renderFailed = false
    /// A slot release is already snapshotting this page: the scroll task must not queue the
    /// same render twice.
    @State private var capturingSnapshot = false
    /// The card's measured width. Until its first layout the card reads the prose column's width
    /// (it spans the column), so a reused cell sizes it right in its first pass instead of
    /// settling a frame later, which moved the text below while the transcript scrolled.
    @State private var measuredWidth: CGFloat = 0
    @Environment(\.richProseWidth) private var proseWidth
    private var width: CGFloat { measuredWidth > 1 ? measuredWidth : proseWidth }
    /// The live document, built when the slot is claimed (never in `body`: R-1).
    @State private var document: String?
    /// The compiled offline rules, awaited before the first load: a chat document must never
    /// paint unprotected. Snapshots and the offline CSP cover the gap.
    @State private var contentRules: WKContentRuleList?
    /// The compile finished, successfully or not: a failed compile still falls back to a
    /// snapshot instead of waiting forever.
    @State private var rulesLoaded = false

    @Environment(\.richViewportHeight) private var viewportHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.richActions) private var richActions

    private var dark: Bool { colorScheme == .dark }

    /// A page that wants more than this gets the "Open" affordance instead.
    private var heightCap: CGFloat { viewportHeight * 0.7 }

    /// The aspect the page had when it was measured, so a revisit reserves its real height
    /// before anything renders.
    private var aspectKey: String { "web:\(contentKey)|\(dark ? "d" : "l")" }

    private var resolvedSnapshot: UIImage? {
        snapshot ?? RichSnapshotCache.lastImage(for: contentKey, dark: dark)
    }

    private var snapshotAspect: CGFloat? {
        guard let snapshot = resolvedSnapshot, snapshot.size.width > 1,
            snapshot.size.height > 1
        else { return nil }
        return snapshot.size.width / snapshot.size.height
    }

    /// The artifact page outranks transcript slots (G4/G5): while it is open the card
    /// shows its snapshot, never a live view.
    private var pageOpen: Bool { richActions?.artifactPageOpen ?? false }

    /// Live only on a first visit, with a slot, without the page, and with the compiled
    /// rules: a chat document must never paint unprotected.
    private var showsLive: Bool {
        isVisible && holdsSlot && !pageOpen && contentRules != nil
            && !prefersSnapshot && snapshot == nil
    }

    /// The height the card reserves. Until the page has measured itself it comes from the
    /// aspect a previous visit remembered (else a calm default), never from a guess at the
    /// content: the same box on every visit.
    private var stageHeight: CGFloat {
        if measuredHeight { return contentHeight }
        if width > 1, let aspect = MediaMetadataCache.aspectRatio(for: aspectKey) ?? snapshotAspect,
            aspect > 0
        {
            return min(max(width / aspect, WebCardMetrics.minimumHeight), heightCap)
        }
        return min(WebCardMetrics.reservedHeight, heightCap)
    }

    var body: some View {
        PaseoCard(content:
            VStack(alignment: .leading, spacing: 10) {
                RichCardSourceHeader(title: kind.title, showSource: $showSource)
                if showSource {
                    RichSourcePanel(code: code)
                } else {
                    stage
                    if overflows {
                        RichOpenButton(
                            accessibilityText: "Open full screen", action: openArtifactPage)
                    }
                }
            })
        .background { widthReader }
        .task { await loadRules() }
        .onAppear {
            if RichSnapshotCache.lastImage(for: contentKey, dark: dark) != nil {
                prefersSnapshot = true
            }
            setVisible(true)
        }
        .onDisappear { setVisible(false) }
        .onScrollVisibilityChange(threshold: 0.1) { visible in setVisible(visible) }
        .onChange(of: pageOpen) { _, open in
            // The page outranks this slot: yield it with a snapshot. Closing the page leaves
            // the card on that snapshot (it is the picture the live view showed).
            if open {
                if holdsSlot { releaseSlot() }
            } else if isVisible {
                claimSlot()
            }
        }
        .onChange(of: colorScheme) { _, _ in
            // The document and the snapshot bake the scheme in; drop both, then rebuild
            // the live document (or let the snapshot path render the new scheme).
            document = nil
            snapshot = nil
            prefersSnapshot = false
            if holdsSlot { document = makeDocument() }
        }
        .task(id: snapshotKey) { await captureSnapshotIfNeeded() }
        .paseoCardMenu(
            openTitle: "Open",
            onOpen: { openArtifactPage() },
            copyTitle: "Copy source",
            copyText: code,
            viewSourceTitle: showSource ? "Hide source" : "View source",
            onViewSource: { showSource.toggle() })
    }

    @ViewBuilder private var stage: some View {
        if showsLive, let document {
            SandboxedHTMLView(
                html: document,
                heightFloor: WebCardMetrics.minimumHeight,
                heightCeiling: heightCap,
                onHeightChange: { setMeasuredHeight($0) },
                onOverflowChange: { overflows = $0 },
                contentRuleList: contentRules,
                awaitContentRules: true)
            .frame(height: stageHeight)
            .animation(Motion.disclosure.resolved(reduceMotion: reduceMotion), value: stageHeight)
        } else if let snapshot = resolvedSnapshot {
            Image(uiImage: snapshot)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: stageHeight)
        } else if renderFailed {
            // Honest and calm in the same box: the source is what the renderer could not
            // turn into a page. No endless spinner (common rules).
            RichSourcePanel(code: code)
        } else {
            Rectangle()
                .fill(Palette.codeSurface)
                .frame(height: stageHeight)
                .overlay { ProgressView().controlSize(.small).tint(Palette.secondaryInk) }
        }
    }

    /// The card's inner width, for snapshots at the real size instead of a guess.
    private var widthReader: some View {
        // `onGeometryChange` on the clear background instead of a `GeometryReader` per card (W1): same
        // size, delivered at once and on change, written only when it differs.
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if measuredWidth != newWidth { measuredWidth = newWidth }
            }
    }

    /// Nil while the live view is (or is about to be) the shown content. A card that will
    /// not go live — off screen, no slot, the page is open, or the rules failed — renders
    /// through the shared offscreen renderer and caches the result.
    private var snapshotKey: String? {
        guard width > 1, !showsLive, !capturingSnapshot, resolvedSnapshot == nil else {
            return nil
        }
        // The rules compile in milliseconds; snapshotting before they land would freeze a
        // card that was about to go live into a snapshot it never asked for.
        if isVisible, !pageOpen, !rulesLoaded, contentRules == nil { return nil }
        return RichSnapshotCache.key(content: contentKey, width: width, dark: dark)
    }

    /// A whole page: a full document gets the offline CSP injected; a fragment gets the
    /// sandboxed shell.
    private func makeDocument() -> String {
        switch kind {
        case .visualize: RichHTMLDocument.visualize(code: code, dark: dark)
        case .html: RichHTMLDocument.artifactHTML(source: code, dark: dark)
        }
    }

    private var artifactDocument: ArtifactDocument {
        switch kind {
        case .visualize: ArtifactDocument(kind: .visualize(code: code), shareImage: nil)
        case .html: ArtifactDocument(kind: .html(source: code, fileName: nil), shareImage: nil)
        }
    }

    /// Open goes to the artifact page (G5 C8): the live stage, source toggle, Reload
    /// and Share as .html live there, not in a transcript sheet.
    private func openArtifactPage() {
        richActions?.openArtifact(artifactDocument)
    }

    @MainActor
    private func loadRules() async {
        guard !rulesLoaded else { return }
        contentRules = await OfflineContentRules.list()
        rulesLoaded = true
    }

    /// Takes the slot when one is free and this card has never snapshotted; on the way out
    /// it snapshots first, so the card has something to show if it comes back — or stays off
    /// screen — without a live web view.
    @MainActor
    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        if visible {
            claimSlot()
        } else if holdsSlot {
            releaseSlot()
        }
    }

    @MainActor
    private func claimSlot() {
        guard !holdsSlot, !pageOpen, !prefersSnapshot, snapshot == nil else { return }
        guard WebViewSlotPool.shared.claim() else { return }
        holdsSlot = true
        if document == nil { document = makeDocument() }
    }

    @MainActor
    private func releaseSlot() {
        guard holdsSlot else { return }
        holdsSlot = false
        WebViewSlotPool.shared.release()
        let renderWidth = width
        guard renderWidth > 1 else { return }
        let key = RichSnapshotCache.key(content: contentKey, width: renderWidth, dark: dark)
        if RichSnapshotCache.image(for: key) != nil { return }
        let html = document ?? makeDocument()
        let renderDark = dark
        capturingSnapshot = true
        Task { @MainActor in
            let rendered = await RichSnapshotQueue.shared.snapshot(
                html: html, width: renderWidth, scale: displayScale, maxHeight: heightCap)
            capturingSnapshot = false
            guard let rendered else { return }
            RichSnapshotCache.store(rendered, for: key, content: contentKey, dark: renderDark)
            // A scheme change while the snapshot rendered made it the wrong picture.
            guard renderDark == dark else { return }
            noteOverflow(in: rendered, at: renderWidth)
            // The card may have scrolled back and reclaimed a slot while this rendered:
            // its live view stays, and the image is only a cache for the next visit.
            if snapshot == nil, !holdsSlot { snapshot = rendered }
        }
    }

    /// A snapshot as tall as the card's cap was clipped by it: the page is at least that tall,
    /// so the card shows the same "Open" the live view would have shown.
    @MainActor
    private func noteOverflow(in image: UIImage, at renderWidth: CGFloat) {
        guard heightCap > 1, image.size.width > 1, renderWidth > 1 else { return }
        let height = image.size.height * (renderWidth / image.size.width)
        if height >= heightCap - 0.5 { overflows = true }
    }

    /// The page's own load-time height, once. Later reports are ignored here as well as in
    /// the coordinator: a growing page never moves the row above it.
    @MainActor
    private func setMeasuredHeight(_ height: CGFloat) {
        guard !measuredHeight, height > 1, width > 1 else { return }
        measuredHeight = true
        contentHeight = min(max(height, WebCardMetrics.minimumHeight), heightCap)
        MediaMetadataCache.remember(width / height, for: aspectKey)
    }

    @MainActor
    private func captureSnapshotIfNeeded() async {
        guard let key = snapshotKey else { return }
        if let cached = RichSnapshotCache.image(for: key) {
            snapshot = cached
            return
        }
        let renderWidth = width
        let rendered = await RichSnapshotQueue.shared.snapshot(
            html: makeDocument(), width: renderWidth, scale: displayScale, maxHeight: heightCap)
        guard !Task.isCancelled else { return }
        guard let rendered else {
            renderFailed = true
            return
        }
        RichSnapshotCache.store(rendered, for: key, content: contentKey, dark: dark)
        noteOverflow(in: rendered, at: renderWidth)
        // Scrolled back before the render landed: the live view is showing and keeps the
        // slot; the image waits in the cache for the next visit.
        guard !holdsSlot else { return }
        snapshot = rendered
        guard !measuredHeight, rendered.size.width > 1, rendered.size.height > 1 else {
            return
        }
        measuredHeight = true
        let pageHeight = min(
            max(rendered.size.height * (renderWidth / rendered.size.width),
                WebCardMetrics.minimumHeight),
            heightCap)
        contentHeight = pageHeight
        MediaMetadataCache.remember(renderWidth / pageHeight, for: aspectKey)
    }
}
#endif
