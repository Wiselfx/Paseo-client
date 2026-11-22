#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

/// The unified diff for one changed file: pinned hunk headers, old/new line numbers, monospaced
/// lines on a horizontal scroll view (long lines are never wrapped), and added/removed rows
/// tinted with the shared diff palette.
///
/// The model is built once per `DiffKey` in `@State`; rows are values (they never re-read the
/// model), so rendering is linear even for a large diff.
struct WorkspaceChangesDiffView: View {
    let file: ParsedDiffFile
    let extras: WorkspaceGitExtras
    /// Commit diffs can't be discarded; hide the destructive affordance there.
    var allowsDiscard = true
    /// Review-comment scope (ignored when nil — the page passes it for the workspace's diff).
    var workspaceId: String? = nil
    /// `uncommitted` | `base` for the review draft scope key.
    var mode = "uncommitted"
    /// The base ref the scope key names when mode == "base".
    var baseRef: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.toast) private var toast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var confirmDiscard = false
    @State private var discardError: String?
    @AppStorage(PaseoSettingsKeys.diffHideWhitespace) private var hideWhitespace = false
    @AppStorage(PaseoSettingsKeys.diffWrapLongLines) private var wrapLongLines = false
    @AppStorage(PaseoSettingsKeys.diffCollapseAllHunks) private var collapseAllHunks = false
    @State private var expandedHunks: Set<Int> = []
    @State private var collapsedHunks: Set<Int> = []
    /// Hunks over 400 lines start collapsed to 40; these are the ones the reader expanded.
    @State private var expandedLongHunks: Set<Int> = []
    /// The built rows, once per input. Nothing in `body` parses the diff.
    @State private var render: DiffRender?
    /// Line-range selection (anchor first, then the end tap).
    @State private var selectionAnchor: LineAnchor?
    @State private var selectionEnd: LineAnchor?
    /// The open comment sheet: a new comment for an anchor, or an existing draft being edited.
    @State private var commentTarget: CommentSheetTarget?

    // MARK: Review drafts

    /// Review drafts are only wired to workspace diffs; commit diffs pass no workspace id
    /// and get an inert page.
    private var reviewEnabled: Bool { workspaceId != nil }

    /// The draft scope for this file's diff. The workspace id is required; without it the
    /// drafting UI is inert but harmless (a single shared scope).
    private var reviewKey: WorkspaceReviewDraftKey {
        WorkspaceReviewDraftKey(
            workspaceId: workspaceId ?? "review-drafts-unknown-workspace",
            mode: mode, baseRef: baseRef ?? "", ignoreWhitespace: hideWhitespace)
    }

    /// The drafts anchored to this file, oldest first.
    private var fileDrafts: [WorkspaceReviewDraftComment] {
        WorkspaceReviewDrafts.shared.comments(for: reviewKey)
            .filter { $0.filePath == file.path }
    }

    /// Grouped once per body evaluation instead of filtering every draft for every row.
    private var draftsByAnchor: [LineAnchor: [WorkspaceReviewDraftComment]] {
        guard reviewEnabled else { return [:] }
        return Dictionary(grouping: fileDrafts) {
            LineAnchor(side: $0.side, line: $0.endLine)
        }
    }

    private var selectionLineRange: (start: Int, end: Int)? {
        guard let anchor = selectionAnchor, let end = selectionEnd else { return nil }
        return (min(anchor.line, end.line), max(anchor.line, end.line))
    }

    private func isInSelectedRange(_ anchor: LineAnchor) -> Bool {
        guard let start = selectionAnchor, let range = selectionLineRange,
            anchor.side == start.side
        else { return false }
        return anchor.line >= range.start && anchor.line <= range.end
    }

    /// The snippet shown in the comment sheet: the target line's text, truncated.
    private func snippet(for anchor: LineAnchor) -> String? {
        guard let render else { return nil }
        for section in render.sections {
            if let row = section.rows.first(where: { $0.anchor == anchor }) { return row.text }
        }
        return nil
    }

    /// The floating capsule while a line range is selected.
    @ViewBuilder private var selectionCapsule: some View {
        if reviewEnabled, let anchor = selectionAnchor, let range = selectionLineRange {
            DiffSelectionCapsule(count: range.end - range.start + 1) {
                commentTarget = .new(LineAnchor(side: anchor.side, line: range.end))
            } onClear: {
                clearSelection()
            }
            .padding(.trailing, Space.lg)
            .padding(.bottom, Space.md)
            .transition(reduceMotion ? .identity : .opacity)
        }
    }

    private func clearSelection() {
        selectionAnchor = nil
        selectionEnd = nil
    }

    private func handle(_ action: DiffLineAction, at anchor: LineAnchor?) {
        switch action {
        case .tap:
            handleRowTap(anchor)
        case .comment:
            if let anchor { commentTarget = .new(anchor) }
        case .startSelection:
            selectionAnchor = anchor
            selectionEnd = nil
        case .extendSelection:
            Haptics.selection()
            if let anchor, anchor.side == selectionAnchor?.side { selectionEnd = anchor }
        case .clearSelection:
            clearSelection()
        }
    }

    private func handleRowTap(_ anchor: LineAnchor?) {
        guard reviewEnabled, let anchor, selectionAnchor != nil else { return }
        guard anchor.side == selectionAnchor?.side else {
            Haptics.failure()
            return
        }
        selectionEnd = anchor
        Haptics.selection()
    }

    init(
        file: ParsedDiffFile, extras: WorkspaceGitExtras, allowsDiscard: Bool = true,
        workspaceId: String? = nil, mode: String = "uncommitted", baseRef: String? = nil
    ) {
        self.file = file
        self.extras = extras
        self.allowsDiscard = allowsDiscard
        self.workspaceId = workspaceId
        self.mode = mode
        self.baseRef = baseRef
    }

    var body: some View {
        VStack(spacing: 0) {
            DiffPathHeader(file: file)
            ClaudeDivider()
            if let discardError {
                InlineBanner(.failure, title: discardError)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm)
            }
            content(drafts: draftsByAnchor)
        }
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .overlay(alignment: .bottomTrailing) { selectionCapsule }
        .sheet(item: $commentTarget) { target in
            if reviewEnabled {
                reviewCommentSheet(target)
            }
        }
        .task(id: diffKey) {
            await build(diffKey)
        }
        .navigationTitle((file.path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsDiscard, extras.capabilities.supportsDiscardChanges {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        "Discard changes to this file", systemImage: "trash", role: .destructive
                    ) {
                        confirmDiscard = true
                    }
                    .tint(Palette.failureInk)
                    .disabled(extras.isDiscarding)
                    // On the button, so the dialog animates out of it.
                    .confirmationDialog(
                        "Discard changes?",
                        isPresented: $confirmDiscard,
                        titleVisibility: .visible
                    ) {
                        Button("Discard changes", role: .destructive) { performDiscard() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This removes all changes in \(file.path). This cannot be undone.")
                    }
                }
            }
        }
        .paseoFeedback(.selection, trigger: selectionAnchor) { _, new in new != nil }
        .paseoFeedback(.selection, trigger: expandedLongHunks)
        .paseoFeedback(.selection, trigger: collapsedHunks)
        .paseoFeedback(.selection, trigger: expandedHunks)
    }

    // MARK: Build

    /// Everything that changes the rendered rows. The file carries no revision, so a cheap
    /// content signature stands in for one.
    private var diffKey: DiffKey {
        let signature = file.hunks
            .map { "\($0.oldStart):\($0.newStart):\($0.oldCount):\($0.newCount):\($0.lines.count)" }
            .joined(separator: ",")
        return DiffKey(
            path: file.path,
            signature: "\(file.additions)/\(file.deletions)/\(signature)",
            hideWhitespace: hideWhitespace)
    }

    private func build(_ key: DiffKey) async {
        let file = self.file
        let hide = self.hideWhitespace
        let unitWidth = Self.characterWidth()
        let lineCount = file.hunks.reduce(0) { $0 + $1.lines.count }
        let built: DiffRender
        if lineCount > 500 {
            built = await DiffModel.renderOffMain(
                file: file, hideWhitespace: hide, unitWidth: unitWidth)
        } else {
            built = DiffModel.render(file: file, hideWhitespace: hide, unitWidth: unitWidth)
        }
        guard !Task.isCancelled, diffKey == key else { return }
        render = built
    }

    /// The mono advance width, measured once on the main actor (UIKit fonts never cross into the
    /// off-main build).
    private static func characterWidth() -> CGFloat {
        let size = TextRole.code.size
        let font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return ("M" as NSString).size(withAttributes: [.font: font]).width
    }

    // MARK: Review comment sheet

    @ViewBuilder private func reviewCommentSheet(_ target: CommentSheetTarget) -> some View {
        let existing: WorkspaceReviewDraftComment? = {
            if case .edit(let draft) = target { return draft }
            return nil
        }()
        let isEditing = existing != nil
        ReviewCommentSheet(
            title: isEditing ? "Edit review comment" : "Leave a comment",
            targetLabel: targetLabel(target),
            snippet: targetSnippet(target),
            initialBody: existing?.body ?? "",
            isEditing: isEditing,
            onSave: { body in saveComment(target, body: body) },
            onDelete: isEditing ? { deleteComment(target) } : nil,
            onCancel: { commentTarget = nil })
    }

    private func targetSnippet(_ target: CommentSheetTarget) -> String? {
        switch target {
        case .new(let anchor): snippet(for: anchor)
        case .edit(let draft): snippet(for: LineAnchor(side: draft.side, line: draft.endLine))
        }
    }

    private func targetLabel(_ target: CommentSheetTarget) -> String {
        let fileName = (file.path as NSString).lastPathComponent
        switch target {
        case .new(let anchor):
            if let range = selectionLineRange, selectionAnchor?.side == anchor.side {
                return "\(fileName):L\(range.start)–\(range.end)"
            }
            return "\(fileName):L\(anchor.line)"
        case .edit(let draft):
            if draft.startLine == draft.endLine { return "\(fileName):L\(draft.startLine)" }
            return "\(fileName):L\(draft.startLine)–\(draft.endLine)"
        }
    }

    private func saveComment(_ target: CommentSheetTarget, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch target {
        case .new(let anchor):
            if let range = selectionLineRange, selectionAnchor?.side == anchor.side {
                WorkspaceReviewDrafts.shared.add(
                    key: reviewKey, filePath: file.path, side: anchor.side,
                    startLine: range.start, endLine: range.end, body: trimmed)
                selectionAnchor = nil
                selectionEnd = nil
            } else {
                WorkspaceReviewDrafts.shared.add(
                    key: reviewKey, filePath: file.path, side: anchor.side,
                    startLine: anchor.line, endLine: anchor.line, body: trimmed)
            }
        case .edit(let draft):
            WorkspaceReviewDrafts.shared.updateBody(key: reviewKey, id: draft.id, body: trimmed)
        }
        Haptics.light()
        commentTarget = nil
    }

    private func deleteComment(_ target: CommentSheetTarget) {
        if case .edit(let draft) = target {
            WorkspaceReviewDrafts.shared.delete(key: reviewKey, id: draft.id)
            Haptics.light()
        }
        commentTarget = nil
    }

    // MARK: Body

    @ViewBuilder private func content(drafts: [LineAnchor: [WorkspaceReviewDraftComment]]) -> some View {
        switch file.status {
        case .binary:
            EmptyState(
                systemImage: "archivebox",
                title: "Binary file",
                message: "Binary files can't be shown as a diff.")
        case .tooLarge:
            EmptyState(
                systemImage: "doc.text",
                title: "File too large",
                message: "The diff for this file was omitted by the host.")
        default:
            if let render {
                if render.sections.isEmpty {
                    EmptyState(
                        systemImage: "checkmark.circle",
                        title: "No textual changes",
                        message: "There's nothing to show for this file.")
                } else {
                    diffScroll(render: render, drafts: drafts)
                }
            } else {
                LoadingState()
            }
        }
    }

    private func isCollapsed(_ hunk: Int) -> Bool {
        if collapsedHunks.contains(hunk) { return true }
        if expandedHunks.contains(hunk) { return false }
        return collapseAllHunks
    }

    private func toggleHunk(_ hunk: Int) {
        if isCollapsed(hunk) {
            expandedHunks.insert(hunk)
            collapsedHunks.remove(hunk)
        } else {
            collapsedHunks.insert(hunk)
            expandedHunks.remove(hunk)
        }
    }

    /// Hunks over 400 lines start at their first 40.
    private func isLongCollapsed(_ section: DiffSection) -> Bool {
        section.rows.count > 400 && !expandedLongHunks.contains(section.hunk)
    }

    private func visibleRows(_ section: DiffSection) -> [DiffModel.Row] {
        if isCollapsed(section.hunk) { return [] }
        if isLongCollapsed(section) { return Array(section.rows.prefix(40)) }
        return section.rows
    }

    // MARK: Scroll

    @ViewBuilder private func diffScroll(
        render: DiffRender, drafts: [LineAnchor: [WorkspaceReviewDraftComment]]
    ) -> some View {
        if wrapLongLines {
            ScrollView(.vertical) {
                stack(render: render, drafts: drafts)
            }
            .background(Palette.codeSurface)
            .codeTypeScale()
        } else {
            // One two-axis ScrollView around the stack. The ticket's nested alternative (a
            // horizontal ScrollView inside the vertical one) leaves the LazyVStack with a
            // horizontal scroll ancestor, which breaks vertical laziness and pinning. A single
            // ScrollView knows both viewport axes, so rows stay lazy, hunk headers pin, and every
            // row shares the same horizontal offset. `totalWidth` is set once on the stack.
            ScrollView([.vertical, .horizontal]) {
                stack(render: render, drafts: drafts)
                    .frame(width: render.totalWidth, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.codeSurface)
            .codeTypeScale()
        }
    }

    private func stack(
        render: DiffRender, drafts: [LineAnchor: [WorkspaceReviewDraftComment]]
    ) -> some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(render.sections) { section in
                Section {
                    let rows = visibleRows(section)
                    ForEach(rows) { row in
                        // One shape per row: a line and its (possibly empty) draft comments.
                        VStack(spacing: 0) {
                            WorkspaceDiffLineRow(
                                row: row, gutterWidth: render.gutterWidth,
                                totalWidth: render.totalWidth, wrap: wrapLongLines,
                                isSelected: row.anchor.map(isInSelectedRange) ?? false,
                                reviewEnabled: reviewEnabled,
                                selectionActive: selectionAnchor != nil
                            ) { action in
                                handle(action, at: row.anchor)
                            }
                            ForEach(row.anchor.flatMap { drafts[$0] } ?? []) { draft in
                                DiffDraftCard(draft: draft) {
                                    commentTarget = .edit(draft)
                                } onDelete: {
                                    WorkspaceReviewDrafts.shared.delete(key: reviewKey, id: draft.id)
                                    Haptics.light()
                                }
                            }
                        }
                    }
                    if isLongCollapsed(section) {
                        DiffShowMoreRow(remaining: max(0, section.rows.count - 40)) {
                            expandedLongHunks.insert(section.hunk)
                        }
                    }
                } header: {
                    DiffHunkHeader(
                        text: section.header, hunk: section.hunk,
                        isCollapsed: isCollapsed(section.hunk)
                    ) {
                        toggleHunk(section.hunk)
                    }
                }
            }
        }
        .padding(.vertical, Space.sm)
    }

    private func performDiscard() {
        Task {
            let discarded = await extras.discard(paths: [file.path])
            if discarded {
                Haptics.light()
                toast?.show("Discarded \(file.path)")
                dismiss()
            } else {
                Haptics.failure()
                discardError = extras.actionError ?? "The discard failed."
            }
        }
    }
}
#endif
