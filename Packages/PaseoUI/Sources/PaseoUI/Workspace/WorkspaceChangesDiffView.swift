#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

/// The unified diff for one changed file: hunk headers, old/new line numbers, monospaced lines
/// on a two-axis scroll view (long lines are never wrapped), and added/removed rows tinted with
/// low-opacity adaptive fills.
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var confirmDiscard = false
    @State private var discardError: String?
    @AppStorage("paseo.diff.hideWhitespace") private var hideWhitespace = false
    @AppStorage("paseo.diff.wrapLongLines") private var wrapLongLines = false
    @AppStorage("paseo.diff.collapseAllHunks") private var collapseAllHunks = false
    @AppStorage("paseo.diff.sideBySide") private var sideBySide = false
    @State private var expandedHunks: Set<Int> = []
    @State private var collapsedHunks: Set<Int> = []
    /// Line-range selection (anchor first, then the end tap); side is fixed at the anchor.
    @State private var selectionAnchor: LineAnchor?
    @State private var selectionEnd: LineAnchor?
    /// The open comment sheet: a new comment for an anchor, or an existing draft being edited.
    @State private var commentTarget: CommentSheetTarget?

    private var model: DiffModel { DiffModel(file: file, hideWhitespaceChanges: hideWhitespace) }
    private var sideModel: SideBySideModel {
        SideBySideModel(file: file, hideWhitespaceChanges: hideWhitespace)
    }
    /// Side-by-side only on regular-width layouts (iPad, landscape Plus); compact iPhones keep
    /// the unified view even if the toggle was set on a wider device.
    private var effectiveSideBySide: Bool {
        sideBySide && horizontalSizeClass == .regular
    }

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
        if let row = model.rows.first(where: { $0.anchor == anchor }) { return row.text }
        for row in sideModel.rows {
            for cell in [row.left, row.right] {
                guard let cell, Int(cell.line) == anchor.line else { continue }
                let side = cell.kind == .remove ? WorkspaceReviewDraftComment.DiffSide.old : .new
                if side == anchor.side || cell.kind == .context { return cell.text }
            }
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
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit review comment")
                    Button {
                        WorkspaceReviewDrafts.shared.delete(key: reviewKey, id: draft.id)
                        Haptics.success()
                    } label: {
                        Image(systemName: "trash")
                            .font(.glyph(.small, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(width: 30, height: 30)
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
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.quoteWash, in: .rect(cornerRadius: Radius.md))
        .padding(.leading, effectiveSideBySide ? 6 : 46)
        .padding(.trailing, 12)
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
            HStack(spacing: 4) {
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
                    .frame(height: 38)
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
                        .background(Palette.ink.opacity(0.85), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear selection")
            }
            .padding(.trailing, 16)
            .padding(.bottom, 12)
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
                Text(discardError)
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.failureInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            content
        }
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .overlay(alignment: .bottomTrailing) { selectionCapsule }
        .sheet(item: $commentTarget) { target in
            if reviewEnabled {
                reviewCommentSheet(target)
            }
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
            Button("Discard Changes", role: .destructive) { performDiscard() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all changes in \(file.path). This cannot be undone.")
        }
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
        Haptics.success()
        commentTarget = nil
    }

    private func deleteComment(_ target: CommentSheetTarget) {
        if case .edit(let draft) = target {
            WorkspaceReviewDrafts.shared.delete(key: reviewKey, id: draft.id)
            Haptics.success()
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
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text("+\(PaseoFormat.integer(file.additions))")
                    .foregroundStyle(Palette.successInk)
                Text("−\(PaseoFormat.integer(file.deletions))")
                    .foregroundStyle(Palette.failureInk)
            }
            .font(.paseo(.codeSmall))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Body

    @ViewBuilder private var content: some View {
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
                subtitle: "The diff for this file was omitted by the daemon.")
        default:
            if model.rows.isEmpty {
                centeredMessage(
                    symbol: "checkmark.circle",
                    title: "No textual changes",
                    subtitle: "There's nothing to show for this file.")
            } else {
                diffScroll
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
        .padding(.horizontal, 32)
    }

    private var visibleRows: [DiffModel.Row] {
        var out: [DiffModel.Row] = []
        for row in model.rows {
            if let hunk = row.hunk, isCollapsed(hunk), row.kind != .hunkHeader { continue }
            out.append(row)
        }
        return out
    }

    private func isCollapsed(_ hunk: Int) -> Bool {
        if collapsedHunks.contains(hunk) { return true }
        if expandedHunks.contains(hunk) { return false }
        return collapseAllHunks
    }

    private var visibleSideRows: [SideBySideModel.Row] {
        sideModel.rows.filter { row in
            if let hunk = row.hunk, row.kind != .hunkHeader {
                return !isCollapsed(hunk)
            }
            return true
        }
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

    private var scrollAxes: Axis.Set { wrapLongLines ? .vertical : [.vertical, .horizontal] }

    private var diffScroll: some View {
        if effectiveSideBySide {
            return AnyView(sideBySideScroll)
        }
        return AnyView(unifiedScroll)
    }

    private var unifiedScroll: some View {
        ScrollView(scrollAxes) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(visibleRows) { row in
                    lineRow(row)
                    ForEach(anchoredDrafts(for: row.anchor)) { draft in
                        draftCard(draft)
                    }
                }
            }
            .padding(.vertical, 8)
            .textSelection(.enabled)
        }
        .background(Palette.codeSurface)
        .codeTypeScale()
    }

    /// Two-column comparison, one HStack per row; each half wraps independently and the row
    /// sizes to the taller half. Never horizontally scrolls.
    private var sideBySideScroll: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(visibleSideRows) { row in
                    sideBySideRow(row)
                    ForEach(sideAnchoredDrafts(for: row)) { draft in
                        draftCard(draft)
                    }
                }
            }
            .padding(.vertical, 8)
            .textSelection(.enabled)
        }
        .background(Palette.codeSurface)
        .codeTypeScale()
    }

    private func sideBySideRow(_ row: SideBySideModel.Row) -> some View {
        Group {
            if row.kind == .hunkHeader, let hunk = row.hunk {
                hunkHeaderRow(text: row.headerText ?? "", hunk: hunk)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    sideCell(row.left)
                    Rectangle()
                        .fill(Palette.divider)
                        .frame(width: 0.5)
                    sideCell(row.right)
                }
                .font(.paseo(.codeSmall))
                .padding(.vertical, 1)
            }
        }
    }

    private func cellAnchor(_ cell: SideBySideModel.Cell?) -> LineAnchor? {
        guard let cell, let line = Int(cell.line) else { return nil }
        let side: WorkspaceReviewDraftComment.DiffSide = cell.kind == .remove ? .old : .new
        return LineAnchor(side: side, line: line)
    }

    private func sideAnchoredDrafts(for row: SideBySideModel.Row) -> [WorkspaceReviewDraftComment] {
        let anchors = [row.left, row.right].compactMap(cellAnchor)
        var out: [WorkspaceReviewDraftComment] = []
        var seen = Set<UUID>()
        for anchor in anchors {
            for draft in anchoredDrafts(for: anchor) where seen.insert(draft.id).inserted {
                out.append(draft)
            }
        }
        return out
    }

    private func sideCell(_ cell: SideBySideModel.Cell?) -> some View {
        // Typed locals: the optional-chained tints inline were too much for the type checker.
        let anchor: LineAnchor? = cellAnchor(cell)
        let lineText: String = cell?.line ?? ""
        let signText: String = cell?.sign ?? " "
        let bodyText: String = {
            guard let text = cell?.text, !text.isEmpty else { return " " }
            return text
        }()
        let signColor: Color = cell.map { signTint($0.kind) } ?? .clear
        let textColor: Color = cell.map { contentTint($0.kind) } ?? Palette.ink
        let fill: Color = selectionWash(anchor)
            ?? cell.map { rowFill($0.kind) }
            ?? Palette.chip.opacity(0.35)
        return Button {
            handleRowTap(anchor)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(lineText)
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 32, alignment: .trailing)
                    .padding(.trailing, 5)
                Text(signText)
                    .foregroundStyle(signColor)
                    .frame(width: 11, alignment: .leading)
                Text(bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(textColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(fill)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if reviewEnabled, let anchor { commentMenu(for: anchor) }
        }
        .accessibilityLabel(cellAccessibilityLabel(cell))
    }

    private func cellAccessibilityLabel(_ cell: SideBySideModel.Cell?) -> String {
        guard let cell else { return "Empty side" }
        let kind: String
        switch cell.kind {
        case .add: kind = "added"
        case .remove: kind = "removed"
        case .context: kind = "context"
        case .hunkHeader: kind = "hunk header"
        }
        return "Line \(cell.line), \(kind): \(cell.text)"
    }

    private func lineRow(_ row: DiffModel.Row) -> some View {
        Group {
            if row.kind == .hunkHeader, let hunk = row.hunk {
                hunkHeaderRow(text: row.text, hunk: hunk)
            } else {
                Button {
                    handleRowTap(row.anchor)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(row.old)
                            .foregroundStyle(Palette.tertiaryInk)
                            .frame(width: 38, alignment: .trailing)
                            .padding(.trailing, 6)
                        Text(row.new)
                            .foregroundStyle(Palette.tertiaryInk)
                            .frame(width: 38, alignment: .trailing)
                            .padding(.trailing, 10)
                        Text(row.sign)
                            .foregroundStyle(signTint(row.kind))
                            .frame(width: 13, alignment: .leading)
                        Text(row.text.isEmpty ? " " : row.text)
                            .fixedSize(horizontal: wrapLongLines ? false : true, vertical: false)
                            .lineLimit(wrapLongLines ? nil : 1)
                            .frame(maxWidth: wrapLongLines ? .infinity : nil, alignment: .leading)
                            .foregroundStyle(contentTint(row.kind))
                    }
                    .font(.paseo(.codeSmall))
                    .frame(width: wrapLongLines ? nil : model.totalWidth, alignment: .leading)
                    .frame(maxWidth: wrapLongLines ? .infinity : nil, alignment: .leading)
                    .padding(.vertical, 2)
                    .background(selectionWash(row.anchor) ?? rowFill(row.kind))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if reviewEnabled, let anchor = row.anchor { commentMenu(for: anchor) }
                }
                .accessibilityLabel(accessibilityLabel(for: row))
            }
        }
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

    /// The drafts anchored to this row, if any.
    private func anchoredDrafts(for anchor: LineAnchor?) -> [WorkspaceReviewDraftComment] {
        guard reviewEnabled, let anchor else { return [] }
        return fileDrafts.filter { $0.side == anchor.side && $0.endLine == anchor.line }
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
            // In a horizontal scroll the parent's width is the widest row; `.infinity` fills it.
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
        case .add: Palette.successInk
        case .remove: Palette.failureInk
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
                Haptics.success()
                dismiss()
            } else {
                Haptics.failure()
                discardError = extras.actionError ?? "The discard failed."
            }
        }
    }
}

// MARK: - Line anchor

/// Where a diff line sits, for review comment anchoring. Context lines anchor on the `new` side.
struct LineAnchor: Hashable {
    let side: WorkspaceReviewDraftComment.DiffSide
    let line: Int
}

// MARK: - Diff line model

/// Flattens a file's hunks into renderable rows with old/new line numbers, and measures the
/// content width so every row can fill the horizontal scroll range.
private struct DiffModel {
    enum RowKind {
        case hunkHeader
        case context
        case add
        case remove
    }

    /// The whitespace filter: a hunk whose changed lines all match on trimmed content carries
    /// no real change (indent moves). Mixed hunks stay. Shared by the unified and the
    /// side-by-side model.
    static func skipHunkForWhitespace(_ hunk: DiffHunk) -> Bool {
        let adds = hunk.lines.compactMap { $0.type == .add ? $0.content : nil }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let removes = hunk.lines.compactMap { $0.type == .remove ? $0.content : nil }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return !adds.isEmpty && adds.count == removes.count && adds.sorted() == removes.sorted()
    }

    struct Row: Identifiable {
        let id: Int
        let old: String
        let new: String
        let sign: String
        let kind: RowKind
        let text: String
        /// Index into `file.hunks`; nil on rows that aren't tied to one (none today).
        var hunk: Int? = nil
        /// Where a review comment would anchor; nil for hunk header rows.
        var anchor: LineAnchor? = nil
    }

    let rows: [Row]
    let totalWidth: CGFloat

    init(file: ParsedDiffFile, hideWhitespaceChanges: Bool = false) {
        var rows: [Row] = []
        var nextId = 0
        for (hunkIndex, hunk) in file.hunks.enumerated() {
            // Client-side whitespace filter: skip hunks whose changed lines all match on
            // trimmed content (indent moves). Mixed hunks stay.
            if hideWhitespaceChanges, Self.skipHunkForWhitespace(hunk) {
                continue
            }
            var oldLine = hunk.oldStart
            var newLine = hunk.newStart
            let hasHeaderLine = hunk.lines.contains { $0.type == .header }
            if !hasHeaderLine {
                rows.append(
                    Row(
                        id: nextId, old: "", new: "", sign: "", kind: .hunkHeader,
                        text: "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@",
                        hunk: hunkIndex))
                nextId += 1
            }
            for line in hunk.lines {
                switch line.type {
                case .header:
                    rows.append(
                        Row(
                            id: nextId, old: "", new: "", sign: "", kind: .hunkHeader,
                            text: line.content, hunk: hunkIndex))
                    nextId += 1
                case .context, .unknown:
                    rows.append(
                        Row(
                            id: nextId, old: "\(oldLine)", new: "\(newLine)", sign: " ",
                            kind: .context, text: line.content, hunk: hunkIndex,
                            anchor: LineAnchor(side: .new, line: newLine)))
                    nextId += 1
                    oldLine += 1
                    newLine += 1
                case .add:
                    rows.append(
                        Row(
                            id: nextId, old: "", new: "\(newLine)", sign: "+",
                            kind: .add, text: line.content, hunk: hunkIndex,
                            anchor: LineAnchor(side: .new, line: newLine)))
                    nextId += 1
                    newLine += 1
                case .remove:
                    rows.append(
                        Row(
                            id: nextId, old: "\(oldLine)", new: "", sign: "-",
                            kind: .remove, text: line.content, hunk: hunkIndex,
                            anchor: LineAnchor(side: .old, line: oldLine)))
                    nextId += 1
                    oldLine += 1
                }
            }
        }
        self.rows = rows

        let font =
            UIFont(name: ClaudeTypography.anthropicMono, size: 12.5)
            ?? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let unit = ("M" as NSString).size(withAttributes: [.font: font]).width
        let gutters: CGFloat = 38 + 6 + 38 + 10 + 13 + 12 + 16
        let longest = rows.map { $0.text.count }.max() ?? 0
        self.totalWidth = max(280, gutters + unit * CGFloat(longest))
    }
}

// MARK: - Side-by-side model

/// Pairs removed/added lines per change block inside each hunk; context lines sit on both
/// sides. Shares the whitespace-hunk filter with the unified model. Long lines are wrapped by
/// the view (side-by-side is an always-wrapped comparison, never a horizontal scroll).
private struct SideBySideModel {
    enum RowKind {
        case hunkHeader
        case context
        case pair
    }

    struct Cell {
        let line: String
        let sign: String
        let text: String
        let kind: DiffModel.RowKind
    }

    struct Row: Identifiable {
        let id: Int
        let kind: RowKind
        let hunk: Int?
        /// Present on .hunkHeader rows (the `@@ … @@` text or an embedded `.header` line).
        let headerText: String?
        let left: Cell?
        let right: Cell?
    }

    let rows: [Row]

    init(file: ParsedDiffFile, hideWhitespaceChanges: Bool = false) {
        var rows: [Row] = []
        var nextId = 0
        for (hunkIndex, hunk) in file.hunks.enumerated() {
            if hideWhitespaceChanges, DiffModel.skipHunkForWhitespace(hunk) {
                continue
            }
            var oldLine = hunk.oldStart
            var newLine = hunk.newStart
            let hasHeaderLine = hunk.lines.contains { $0.type == .header }
            if !hasHeaderLine {
                rows.append(
                    Row(
                        id: nextId, kind: .hunkHeader, hunk: hunkIndex,
                        headerText: "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@",
                        left: nil, right: nil))
                nextId += 1
            }
            var pendingRemoves: [(line: Int, text: String)] = []
            var pendingAdds: [(line: Int, text: String)] = []
            func flushChanges() {
                let count = max(pendingRemoves.count, pendingAdds.count)
                for index in 0 ..< count {
                    let left = index < pendingRemoves.count ? pendingRemoves[index] : nil
                    let right = index < pendingAdds.count ? pendingAdds[index] : nil
                    rows.append(
                        Row(
                            id: nextId, kind: .pair, hunk: hunkIndex, headerText: nil,
                            left: left.map {
                                Cell(line: "\($0.line)", sign: "-", text: $0.text, kind: .remove)
                            },
                            right: right.map {
                                Cell(line: "\($0.line)", sign: "+", text: $0.text, kind: .add)
                            }))
                    nextId += 1
                }
                pendingRemoves.removeAll()
                pendingAdds.removeAll()
            }
            for line in hunk.lines {
                switch line.type {
                case .header:
                    flushChanges()
                    rows.append(
                        Row(
                            id: nextId, kind: .hunkHeader, hunk: hunkIndex,
                            headerText: line.content, left: nil, right: nil))
                    nextId += 1
                case .context, .unknown:
                    flushChanges()
                    rows.append(
                        Row(
                            id: nextId, kind: .context, hunk: hunkIndex, headerText: nil,
                            left: Cell(
                                line: "\(oldLine)", sign: " ", text: line.content, kind: .context),
                            right: Cell(
                                line: "\(newLine)", sign: " ", text: line.content, kind: .context)))
                    nextId += 1
                    oldLine += 1
                    newLine += 1
                case .add:
                    pendingAdds.append((newLine, line.content))
                    newLine += 1
                case .remove:
                    pendingRemoves.append((oldLine, line.content))
                    oldLine += 1
                }
            }
            flushChanges()
        }
        self.rows = rows
    }
}


// MARK: - Comment sheet target

private enum CommentSheetTarget: Identifiable, Hashable {
    case new(LineAnchor)
    case edit(WorkspaceReviewDraftComment)

    var id: String {
        switch self {
        case .new(let anchor): "new:\(anchor.side.rawValue):\(anchor.line)"
        case .edit(let draft): "edit:\(draft.id.uuidString)"
        }
    }
}

/// The "Leave a comment" sheet: the target's quoted snippet, a multiline body, and
/// Cancel / Comment (or Delete / Save when editing). Mirrors upstream's mobile comment sheet.
private struct ReviewCommentSheet: View {
    let title: String
    let targetLabel: String
    let snippet: String?
    let initialBody: String
    let isEditing: Bool
    let onSave: (String) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(
        title: String, targetLabel: String, snippet: String?, initialBody: String,
        isEditing: Bool, onSave: @escaping (String) -> Void, onDelete: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.targetLabel = targetLabel
        self.snippet = snippet
        self.initialBody = initialBody
        self.isEditing = isEditing
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _text = State(initialValue: initialBody)
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title, close: onCancel)
            VStack(alignment: .leading, spacing: 14) {
                Text(targetLabel)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.secondaryInk)
                if let snippet, !snippet.isEmpty {
                    Text("> \(snippet.prefix(200))")
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Palette.quoteWash, in: .rect(cornerRadius: Radius.md))
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Leave a comment")
                            .font(.paseo(.callout))
                            .foregroundStyle(Palette.tertiaryInk)
                            .allowsHitTesting(false)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $text)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120, maxHeight: 240)
                        .focused($focused)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Palette.chip, in: .rect(cornerRadius: Radius.md))
                HStack(spacing: 10) {
                    if let onDelete {
                        Button {
                            onDelete()
                        } label: {
                            Text("Delete")
                                .font(.paseo(.callout, weight: .medium))
                                .foregroundStyle(Palette.failureInk)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(minHeight: 44)
                    Button {
                        guard canSave else { return }
                        onSave(text)
                    } label: {
                        Text(isEditing ? "Save" : "Comment")
                            .font(.paseo(.callout, weight: .semibold))
                            .foregroundStyle(Palette.background)
                            .padding(.horizontal, 22)
                            .frame(minHeight: 44)
                            .background(Palette.ink.opacity(canSave ? 1 : 0.35), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .accessibilityLabel(isEditing ? "Save review comment" : "Save review comment")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .background(Palette.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { focused = true }
    }
}

#endif
