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
    @AppStorage("paseo.diff.hideWhitespace") private var hideWhitespace = false
    @AppStorage("paseo.diff.wrapLongLines") private var wrapLongLines = false
    @AppStorage("paseo.diff.collapseAllHunks") private var collapseAllHunks = false
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

    private func commentMenu(for anchor: LineAnchor) -> some View {
        Group {
            Button("Add review comment…", systemImage: "text.bubble") {
                commentTarget = .new(anchor)
            }
            if selectionAnchor == nil {
                Button("Select line range…", systemImage: "selection.pin.in.out") {
                    Haptics.selection()
                    selectionAnchor = anchor
                    selectionEnd = nil
                }
            } else {
                Button("Extend selection to this line", systemImage: "selection.pin.in.out") {
                    Haptics.selection()
                    if anchor.side == selectionAnchor?.side { selectionEnd = anchor }
                }
                Button("Clear selection", systemImage: "xmark", role: .cancel) {
                    selectionAnchor = nil
                    selectionEnd = nil
                }
            }
        }
    }

    // MARK: Review draft cards

    /// The quiet card rendered inline under the anchor line.
    @ViewBuilder private func draftCard(_ draft: WorkspaceReviewDraftComment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.glyph(.small, weight: .regular))
                .foregroundStyle(Palette.tertiaryInk)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(lineRangeLabel(draft))
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.tertiaryInk)
                    Text("Review comment")
                        .font(.paseo(.caption2, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                    Spacer(minLength: 4)
                    Button {
                        commentTarget = .edit(draft)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.glyph(.small, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(width: 30, height: 30)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit review comment")
                    Button {
                        WorkspaceReviewDrafts.shared.delete(key: reviewKey, id: draft.id)
                        Haptics.light()
                    } label: {
                        Image(systemName: "trash")
                            .font(.glyph(.small, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(width: 30, height: 30)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete review comment")
                }
                Text(draft.body)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture {
                        commentTarget = .edit(draft)
                    }
                    .accessibilityLabel("Review comment: \(draft.body)")
                    .accessibilityHint("Edits the comment")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Palette.quoteWash, in: .rect(cornerRadius: Radius.md))
        .padding(.leading, 46)
        .padding(.trailing, Space.md)
        .padding(.vertical, 3)
    }

    private func lineRangeLabel(_ draft: WorkspaceReviewDraftComment) -> String {
        if draft.startLine == draft.endLine { return "L\(draft.startLine)" }
        return "L\(draft.startLine)–\(draft.endLine)"
    }

    // MARK: Selection capsule

    /// Floating capsule while a line range is selected: "Comment on N lines" + cancel.
    @ViewBuilder private var selectionCapsule: some View {
        if reviewEnabled, let anchor = selectionAnchor, let range = selectionLineRange {
            let count = range.end - range.start + 1
            HStack(spacing: Space.xs) {
                Button {
                    commentTarget = .new(LineAnchor(side: anchor.side, line: range.end))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble")
                            .font(.glyph(.small, weight: .medium))
                        Text("Comment on \(PaseoFormat.integer(count)) \(count == 1 ? "line" : "lines")")
                            .font(.paseo(.footnote, weight: .medium))
                    }
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Palette.ink, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Comment on the selected \(count) lines")
                Button {
                    selectionAnchor = nil
                    selectionEnd = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.background)
                        .frame(width: 38, height: 38)
                        .frame(width: 44, height: 44)
                        .background(Palette.ink.opacity(0.85), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear selection")
            }
            .padding(.trailing, Space.lg)
            .padding(.bottom, Space.md)
            .transition(reduceMotion ? .identity : .opacity)
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
            pathHeader
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
                    Button(role: .destructive) {
                        confirmDiscard = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Palette.failureInk)
                    }
                    .accessibilityLabel("Discard changes to this file")
                    .disabled(extras.isDiscarding)
                }
            }
        }
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
            hideWhitespace: hideWhitespace,
            wrap: wrapLongLines)
    }

    private func build(_ key: DiffKey) async {
        let file = self.file
        let hide = self.hideWhitespace
        let unitWidth = Self.characterWidth()
        let lineCount = file.hunks.reduce(0) { $0 + $1.lines.count }
        let built: DiffRender
        if lineCount > 500 {
            built = await Task.detached(priority: .userInitiated) {
                DiffModel.render(file: file, hideWhitespace: hide, unitWidth: unitWidth)
            }.value
        } else {
            built = DiffModel.render(file: file, hideWhitespace: hide, unitWidth: unitWidth)
        }
        guard !Task.isCancelled, diffKey == key else { return }
        render = built
    }

    /// The mono advance width, measured once on the main actor (UIKit fonts never cross into the
    /// detached build).
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

    // MARK: Path header

    private var pathHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(file.path)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                if let oldPath = file.oldPath {
                    Text("renamed from \(oldPath)")
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: Space.sm)
            DiffStat(added: file.additions, removed: file.deletions)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, 10)
    }

    // MARK: Body

    @ViewBuilder private func content(drafts: [LineAnchor: [WorkspaceReviewDraftComment]]) -> some View {
        switch file.status {
        case .binary:
            centeredMessage(
                symbol: "archivebox",
                title: "Binary file",
                subtitle: "Binary files can't be shown as a diff.")
        case .tooLarge:
            centeredMessage(
                symbol: "doc.text",
                title: "File too large",
                subtitle: "The diff for this file was omitted by the host.")
        default:
            if let render {
                if render.sections.isEmpty {
                    centeredMessage(
                        symbol: "checkmark.circle",
                        title: "No textual changes",
                        subtitle: "There's nothing to show for this file.")
                } else {
                    diffScroll(render: render, drafts: drafts)
                }
            } else {
                LoadingState()
            }
        }
    }

    private func centeredMessage(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.glyph(.hero, weight: .light))
                .foregroundStyle(Palette.tertiaryInk)
            Text(title)
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text(subtitle)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Space.xxxl)
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
                            lineRow(row, totalWidth: render.totalWidth, gutterWidth: render.gutterWidth)
                            ForEach(row.anchor.flatMap { drafts[$0] } ?? []) { draft in
                                draftCard(draft)
                            }
                        }
                    }
                    if isLongCollapsed(section) {
                        showMoreRow(section)
                    }
                } header: {
                    hunkHeaderRow(text: section.header, hunk: section.hunk)
                }
            }
        }
        .padding(.vertical, Space.sm)
    }

    // MARK: Rows

    private func lineRow(_ row: DiffModel.Row, totalWidth: CGFloat, gutterWidth: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(row.old.isEmpty ? " " : row.old)
                .font(.paseo(.codeCaption))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: gutterWidth, alignment: .trailing)
            Text(row.new.isEmpty ? " " : row.new)
                .font(.paseo(.codeCaption))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: gutterWidth, alignment: .trailing)
                .padding(.trailing, 10)
            Text(row.sign)
                .font(.paseo(.code))
                .foregroundStyle(signTint(row.kind))
                .frame(width: 13, alignment: .leading)
            Text(row.text.isEmpty ? " " : row.text)
                .font(.paseo(.code))
                .lineLimit(wrapLongLines ? nil : 1)
                .fixedSize(horizontal: !wrapLongLines, vertical: false)
                .frame(
                    maxWidth: wrapLongLines ? .infinity : nil,
                    alignment: .leading)
                .foregroundStyle(contentTint(row.kind))
        }
        .frame(width: wrapLongLines ? nil : totalWidth, alignment: .leading)
        .frame(maxWidth: wrapLongLines ? .infinity : nil, alignment: .leading)
        .padding(.vertical, 2)
        .background(selectionWash(row.anchor) ?? rowFill(row.kind))
        .contentShape(.rect)
        .onTapGesture { handleRowTap(row.anchor) }
        .contextMenu {
            Button("Copy line", systemImage: "doc.on.doc") {
                Clipboard.copy(row.text)
            }
            if reviewEnabled, let anchor = row.anchor {
                Divider()
                commentMenu(for: anchor)
            }
        }
        .accessibilityLabel(accessibilityLabel(for: row))
        .accessibilityAddTraits(reviewEnabled && row.anchor != nil ? .isButton : [])
    }

    private func showMoreRow(_ section: DiffSection) -> some View {
        let remaining = max(0, section.rows.count - 40)
        return HStack(spacing: Space.sm) {
            Image(systemName: "chevron.down")
                .font(.glyph(.small, weight: .semibold))
                .foregroundStyle(Palette.secondaryInk)
            Text("Show \(PaseoFormat.integer(remaining)) more lines")
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chip)
        .contentShape(.rect)
        .onTapGesture {
            Haptics.selection()
            expandedLongHunks.insert(section.hunk)
        }
        .accessibilityLabel("Show \(remaining) more lines")
        .accessibilityAddTraits(.isButton)
    }

    private func selectionWash(_ anchor: LineAnchor?) -> Color? {
        guard let anchor, isInSelectedRange(anchor) else { return nil }
        return Palette.warning.opacity(0.16)
    }

    private func accessibilityLabel(for row: DiffModel.Row) -> String {
        switch row.kind {
        case .add: "Added line \(row.new): \(row.text)"
        case .remove: "Removed line \(row.old): \(row.text)"
        case .context, .hunkHeader: "Line \(row.new): \(row.text)"
        }
    }

    private func hunkHeaderRow(text: String, hunk: Int) -> some View {
        Button {
            Haptics.selection()
            toggleHunk(hunk)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Image(systemName: isCollapsed(hunk) ? "chevron.right" : "chevron.down")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 14)
                Text(text)
                    .foregroundStyle(contentTint(.hunkHeader))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.paseo(.codeSmall))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .background(rowFill(.hunkHeader))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hunk \(hunk + 1), \(isCollapsed(hunk) ? "collapsed" : "expanded")")
    }

    private func contentTint(_ kind: DiffModel.RowKind) -> Color {
        switch kind {
        case .hunkHeader: Palette.tertiaryInk
        case .context, .add, .remove: Palette.ink
        }
    }

    private func signTint(_ kind: DiffModel.RowKind) -> Color {
        switch kind {
        case .add: Palette.diffAddedInk
        case .remove: Palette.diffRemovedInk
        case .context, .hunkHeader: .clear
        }
    }

    private func rowFill(_ kind: DiffModel.RowKind) -> Color {
        switch kind {
        case .add: Palette.diffAdded
        case .remove: Palette.diffRemoved
        case .hunkHeader: Palette.chip
        case .context: .clear
        }
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
