#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One provider subagent's timeline, read-only: the tail page, plain rows, and older pages
/// prepended as the reader reaches the top (`E3b`).
///
/// The prepend is compensated exactly like the main transcript (`ChatTranscript.swift:526`): the
/// content height and offset are captured when the page is requested, and when the content has
/// grown the offset is set to `offsetY + growth`. No scroll-to-row and no `Task.yield`: a frame
/// that renders between the insert and a scroll would show the jump. The loading spinner is an
/// overlay, so it never moves a row. One older request in flight at a time.
struct ChatSubagentTimelineView: View {
    let subagents: ConversationSubagents
    let subagent: ProviderSubagent

    @State private var rows: [ProviderSubagentTimelineRequest.Response.Row] = []
    @State private var loading = true
    @State private var error: String?
    @State private var olderError: String?
    @State private var loadingOlder = false
    @State private var hasOlder = false
    /// The oldest row loaded: the page before it is what "older" means.
    @State private var startCursor: TimelineCursor?
    /// Where the viewport sat when an older page was requested, so the prepend can be undone.
    @State private var olderAnchor: OlderAnchor?
    /// The last scroll geometry, so the retry button can ask again without a scroll.
    @State private var metrics: Metrics?
    /// U3-style position; used only to undo a prepend.
    @State private var scrollPosition = ScrollPosition()

    private static let pageSize = 50
    /// How close to the top asks for the next page.
    private static let loadSlack: CGFloat = 24

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if loading && rows.isEmpty {
                    LoadingState()
                        .padding(.top, 60)
                } else if let error {
                    VStack(spacing: Space.md) {
                        InlineBanner(
                            .failure, title: error,
                            action: ("Try again", { Task { await load() } }))
                    }
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity)
                } else if rows.isEmpty {
                    // Upstream's timeline panel empty line (`en.ts:233`, `agentStream.empty`).
                    EmptyState(title: "Start chatting with this agent...")
                        .padding(.top, 60)
                } else {
                    if let olderError {
                        InlineBanner(
                            .failure, title: olderError,
                            action: ("Try again", { retryOlder() }))
                    }
                    ForEach(rows, id: \.seq) { row in
                        SubagentTimelineRow(row: row)
                    }
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, 18)
        }
        .scrollPosition($scrollPosition)
        // Overlaid, so the spinner appearing or leaving never shifts the content (UX spec §4.3).
        .overlay(alignment: .top) {
            if loadingOlder {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Loading earlier messages")
            }
        }
        .onScrollGeometryChange(for: Metrics.self) { geometry in
            Metrics(
                contentHeight: geometry.contentSize.height,
                offsetY: geometry.contentOffset.y,
                viewportHeight: geometry.bounds.height)
        } action: { _, new in
            metrics = new
            handleScroll(new)
        }
        .background(Palette.background)
        .navigationTitle(rowTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var rowTitle: String {
        subagent.title ?? subagent.description ?? subagent.provider
    }

    private struct Metrics: Equatable {
        var contentHeight: CGFloat
        var offsetY: CGFloat
        var viewportHeight: CGFloat
    }

    /// Where the viewport sat when an older page was requested (the transcript's `HistoryAnchor`).
    private struct OlderAnchor {
        var contentHeight: CGFloat
        var offsetY: CGFloat
        var startedAt: Date
        /// The growth already compensated; a correction is re-applied only when the content
        /// grows further, so the reader can scroll freely right after a page lands.
        var appliedGrowth: CGFloat = 0
    }

    private func handleScroll(_ metrics: Metrics) {
        // A prepended page moved the content down by its own height; undo it before anything
        // else reacts to the new offsets.
        if restoreOlderAnchor(metrics) { return }
        loadOlderIfNeeded(metrics)
    }

    private func loadOlderIfNeeded(_ metrics: Metrics) {
        guard hasOlder, !loading, !loadingOlder, olderError == nil, let cursor = startCursor
        else { return }
        // At the top, or on a page too short to scroll (the top is in view at every offset).
        guard metrics.offsetY <= Self.loadSlack
            || metrics.contentHeight <= metrics.viewportHeight + 1
        else { return }
        loadingOlder = true
        olderAnchor = OlderAnchor(
            contentHeight: metrics.contentHeight, offsetY: metrics.offsetY, startedAt: .now)
        Task { await fetchOlder(cursor: cursor) }
    }

    /// Undoes a prepend by scrolling down by the height the content above the viewport grew.
    /// Returns true when it scrolled, so the trigger check is skipped for that frame.
    private func restoreOlderAnchor(_ metrics: Metrics) -> Bool {
        guard let anchor = olderAnchor else { return false }
        if Date.now.timeIntervalSince(anchor.startedAt) > 2 {
            olderAnchor = nil
            return false
        }
        let growth = metrics.contentHeight - anchor.contentHeight
        if growth > 1, abs(growth - anchor.appliedGrowth) > 1 {
            olderAnchor?.appliedGrowth = growth
            scrollPosition.scrollTo(y: anchor.offsetY + growth)
            return true
        }
        if !loadingOlder { olderAnchor = nil }
        return false
    }

    @MainActor
    private func fetchOlder(cursor: TimelineCursor) async {
        defer { loadingOlder = false }
        guard let page = await subagents.timelinePage(
            for: subagent.id, before: cursor, limit: Self.pageSize)
        else {
            olderError = subagents.error ?? "Couldn't load the timeline."
            olderAnchor = nil
            return
        }
        let known = Set(rows.map(\.seq))
        let older = page.rows.filter { !known.contains($0.seq) }
        rows = older + rows
        startCursor = page.startCursor
        hasOlder = page.hasOlder ?? false
        if older.isEmpty {
            // Nothing was prepended: nothing to compensate, and the same cursor would ask again.
            olderAnchor = nil
            hasOlder = false
        }
    }

    private func retryOlder() {
        olderError = nil
        if let metrics { loadOlderIfNeeded(metrics) }
    }

    @MainActor
    private func load() async {
        loading = true
        if let page = await subagents.timelinePage(for: subagent.id, limit: Self.pageSize) {
            rows = page.rows
            startCursor = page.startCursor
            hasOlder = page.hasOlder ?? false
            olderError = nil
            olderAnchor = nil
            error = nil
        } else {
            error = subagents.error ?? "Couldn't load the timeline."
        }
        loading = false
    }
}
#endif
