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
                DiffSheetScroll(lines: lines, wrap: wrapLongLines)
            } else {
                DiffInlinePreview(
                    lines: lines, wrap: wrapLongLines,
                    document: ClaudeDiffDocument(
                        path: path, unifiedDiff: unifiedDiff, old: old, new: new))
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
                ToolbarItem(placement: .topBarTrailing) {
                    DiffOptionsMenu(hideWhitespace: $hideWhitespace, wrapLongLines: $wrapLongLines)
                }
            }
        }
    }
}
#endif
