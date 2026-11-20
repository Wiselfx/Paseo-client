#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A long text's first lines in mono, sideways-scrollable, with "Show all N lines" opening the rest
/// in a sheet. The head and the count are read once per text (the text is compared by identity
/// first, so an unchanged output costs nothing), never per body pass.
struct ClaudeOutputPreview: View {
    let text: String
    let maxLines: Int

    /// The sheet's line cap: past it a single `Text` stops being responsive.
    static let sheetLines = 2000

    private final class Memo {
        var source: String?
        var maxLines = 0
        var head = ""
        var lineCount = 0
    }

    @State private var memo = Memo()
    @State private var showsAll = false

    private var preview: (head: String, lines: Int) {
        if memo.source != text || memo.maxLines != maxLines {
            memo.source = text
            memo.maxLines = maxLines
            memo.head = Self.head(of: text, lines: maxLines)
            memo.lineCount = Self.lineCount(of: text)
        }
        return (memo.head, memo.lineCount)
    }

    var body: some View {
        let preview = self.preview
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                Text(preview.head)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.ink.opacity(0.85))
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            if preview.lines > maxLines {
                Button("Show all \(PaseoFormat.integer(preview.lines)) lines") { showsAll = true }
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(minHeight: Metrics.hitSize)
                    .padding(.horizontal, 12)
                    .sheet(isPresented: $showsAll) {
                        SheetScaffold("Output", detents: .large) {
                            VStack(alignment: .leading, spacing: 0) {
                                if preview.lines > Self.sheetLines {
                                    Text("Showing the first \(PaseoFormat.integer(Self.sheetLines)) of \(PaseoFormat.integer(preview.lines)) lines")
                                        .font(.paseo(.caption))
                                        .foregroundStyle(Palette.secondaryInk)
                                        .padding(.horizontal, Space.md)
                                        .padding(.vertical, Space.sm)
                                }
                                ScrollView([.vertical, .horizontal]) {
                                    Text(Self.head(of: text, lines: Self.sheetLines))
                                        .font(.paseo(.codeSmall))
                                        .textSelection(.enabled)
                                        .fixedSize()
                                        .padding(Space.md)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
            }
        }
    }

    /// The text up to its `lines`-th line break, without the break.
    static func head(of text: String, lines: Int) -> String {
        var seen = 0
        let utf8 = text.utf8
        var index = utf8.startIndex
        while index != utf8.endIndex {
            if utf8[index] == 10 {
                seen += 1
                if seen == lines { return String(text[..<index]) }
            }
            index = utf8.index(after: index)
        }
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    /// Lines in the text; a trailing break does not start another.
    static func lineCount(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 1
        for byte in text.utf8 where byte == 10 { count += 1 }
        return text.utf8.last == 10 ? count - 1 : count
    }
}
#endif
