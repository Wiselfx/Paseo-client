#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

struct ClaudeDiffView: View {
    let path: String
    let unifiedDiff: String?
    let old: String?
    let new: String?
    /// The chat diff sheet asks for the whole file: it fills the sheet and gets the options menu
    /// in the top bar. Inline, the diff shows its first lines and opens whole in that sheet.
    var fullHeight: Bool = false

    /// Lines an inline diff shows before "Show all".
    static let inlineLines = 24

    /// The same two preferences as the workspace Changes screen (`WorkspaceChangesDiffView`).
    @AppStorage("paseo.diff.hideWhitespace") private var hideWhitespace = false
    @AppStorage("paseo.diff.wrapLongLines") private var wrapLongLines = false
    @Environment(\.chatActions) private var actions

    /// The parse, once per diff: read synchronously on first draw (no empty frame that then grows),
    /// and only again when the diff or the whitespace preference changes. The inputs are compared by
    /// identity first, so an unchanged diff costs nothing per body pass.
    private final class Parse {
        var unifiedDiff: String?
        var old: String?
        var new: String?
        var hideWhitespace = false
        var lines: [ClaudeDiffLine] = []
        var parsed = false
    }

    @State private var parse = Parse()

    private var lines: [ClaudeDiffLine] {
        if !parse.parsed || parse.unifiedDiff != unifiedDiff || parse.old != old || parse.new != new
            || parse.hideWhitespace != hideWhitespace
        {
            let raw = ClaudeDiffLine.parse(unifiedDiff: unifiedDiff, old: old, new: new)
            parse.lines = hideWhitespace ? ClaudeDiffLine.hidingWhitespaceOnly(raw) : raw
            parse.unifiedDiff = unifiedDiff
            parse.old = old
            parse.new = new
            parse.hideWhitespace = hideWhitespace
            parse.parsed = true
        }
        return parse.lines
    }

    var body: some View {
        let lines = self.lines
        VStack(alignment: .leading, spacing: 0) {
            Text(path)
                .font(.paseo(.codeSmall))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, Space.md)
                .padding(.vertical, 9)
            ClaudeDivider()
            if fullHeight {
                sheetScroll(lines)
            } else {
                inline(lines)
            }
        }
        .frame(
            maxWidth: fullHeight ? .infinity : nil,
            maxHeight: fullHeight ? .infinity : nil,
            alignment: .top)
        .background(Palette.codeSurface, in: .rect(cornerRadius: fullHeight ? 0 : Radius.md))
        .overlay {
            if !fullHeight {
                RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.cardBorder, lineWidth: 1)
            }
        }
        .codeTypeScale()
        .toolbar {
            if fullHeight {
                ToolbarItem(placement: .topBarTrailing) { diffOptionsMenu }
            }
        }
    }

    /// The first lines, sideways-scrollable (or wrapped), never a scroller inside the transcript.
    @ViewBuilder private func inline(_ lines: [ClaudeDiffLine]) -> some View {
        let shown = lines.prefix(Self.inlineLines)
        Group {
            if wrapLongLines {
                diffLines(shown, wrap: true)
            } else {
                ScrollView(.horizontal) { diffLines(shown, wrap: false) }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
        if lines.count > Self.inlineLines, let actions {
            Button("Show all \(PaseoFormat.integer(lines.count)) lines") {
                actions.showDiff(
                    ClaudeDiffDocument(path: path, unifiedDiff: unifiedDiff, old: old, new: new))
            }
            .font(.paseo(.caption, weight: .medium))
            .foregroundStyle(Palette.secondaryInk)
            .frame(minHeight: Metrics.hitSize)
            .padding(.horizontal, Space.md)
        }
    }

    /// The whole diff in the sheet: wrap (vertical scroll only) or scroll both ways. Upstream:
    /// packages/app/src/git/diff-pane.tsx:842-847 (wrap vs scroll labels).
    @ViewBuilder private func sheetScroll(_ lines: [ClaudeDiffLine]) -> some View {
        if wrapLongLines {
            ScrollView(.vertical) { lazyLines(lines, wrap: true) }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: .infinity)
        } else {
            ScrollView([.vertical, .horizontal]) { lazyLines(lines, wrap: false) }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: .infinity)
        }
    }

    private func diffLines(_ lines: ArraySlice<ClaudeDiffLine>, wrap: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in lineView(line, wrap: wrap) }
        }
        .padding(.vertical, 6)
        .textSelection(.enabled)
    }

    private func lazyLines(_ lines: [ClaudeDiffLine], wrap: Bool) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in lineView(line, wrap: wrap) }
        }
        .padding(.vertical, 6)
        .textSelection(.enabled)
    }

    private func lineView(_ line: ClaudeDiffLine, wrap: Bool) -> some View {
        Text(line.text.isEmpty ? " " : line.text)
            .font(.paseo(.codeSmall))
            .foregroundStyle(line.kind == .header ? Palette.tertiaryInk : Palette.ink)
            .fixedSize(horizontal: !wrap, vertical: true)
            .padding(.horizontal, Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background(for: line.kind))
    }

    /// The three-dot menu in the sheet's top bar. Upstream: packages/app/src/git/diff-pane.tsx:883-897
    /// (the two items); the words are en.ts `workspace.git.diff` (`options`, `hideWhitespace`,
    /// `showWhitespace`, `wrapLongLines`, `scrollLongLines`), packages/app/src/i18n/resources/en.ts:981-986.
    private var diffOptionsMenu: some View {
        Menu {
            Toggle(isOn: $hideWhitespace) {
                Text(hideWhitespace ? "Show whitespace" : "Hide whitespace")
            }
            .tint(Palette.toggleTint)
            Toggle(isOn: $wrapLongLines) {
                Text(wrapLongLines ? "Scroll long lines" : "Wrap long lines")
            }
            .tint(Palette.toggleTint)
        } label: {
            Image(systemName: "ellipsis")
                .font(.glyph(.small, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Diff options")
    }

    private func background(for kind: ClaudeDiffLine.Kind) -> Color {
        switch kind {
        case .added: Palette.diffAdded
        case .removed: Palette.diffRemoved
        case .context, .header: .clear
        }
    }
}
#endif
