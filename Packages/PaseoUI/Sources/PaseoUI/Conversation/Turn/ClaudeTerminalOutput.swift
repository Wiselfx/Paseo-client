#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The tail in ANSI colors, with "Show all" opening the capped sheet. Until the
/// first parse lands, the plain last 12 lines hold the final box height and only
/// the colors change — no jump, no repeated work on remount. The sheet builds its
/// colored text when it presents, for the last lines it shows: 200 at first, more on request.
struct ClaudeTerminalOutput: View {
    let output: String
    /// The parse `ClaudeCodeBlock` holds; nil until the first one lands.
    let parsed: ClaudeCodeBlock.ParsedTerminal?

    /// The sheet's first page: the last 200 lines, so opening a huge log lays out 200 lines,
    /// not the 2,000 the parse keeps.
    nonisolated static let sheetFirstLines = 200
    /// What each "Show more" tap adds to the page.
    nonisolated static let sheetStepLines = 400

    @State private var showAll = false
    /// How many of the sheet's last lines are laid out. Each open starts again at `sheetFirstLines`.
    @State private var sheetCap = ClaudeTerminalOutput.sheetFirstLines

    var body: some View {
        let display = parsed ?? TerminalParseCache.entry(for: output)
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                if let display {
                    Text(display.tailAttributed)
                        .font(.paseo(.codeSmall))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(AnsiText.plainTail(output, maxLines: ClaudeCodeBlock.tailLines))
                        .font(.paseo(.codeSmall))
                        .foregroundStyle(Palette.ink.opacity(0.85))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            if let display, display.lineCount > ClaudeCodeBlock.tailLines {
                Button("Show all \(PaseoFormat.integer(display.lineCount)) lines", action: openSheet)
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(minHeight: Metrics.hitSize)
                    .accessibilityHint("Opens the full terminal output")
                    .sheet(isPresented: $showAll) {
                        // Built here, on presentation: only the lines this sheet lays out become
                        // colored text, never the whole 2,000-line parse.
                        let visible = AnsiText.tail(display.sheet, maxLines: sheetCap)
                        // The tail keeps whole lines, and a dropped line always carries its
                        // terminator, so fewer bytes than the sheet holds means lines were left out.
                        let hasMore = Self.byteCount(visible) < Self.byteCount(display.sheet)
                        let shownLines = hasMore ? sheetCap : ClaudeCodeBlock.sheetLines
                        OutputSheet(
                            note: (hasMore || display.lineCount > ClaudeCodeBlock.sheetLines)
                                ? Text(
                                    "Showing the last \(PaseoFormat.integer(shownLines)) of \(PaseoFormat.integer(display.lineCount)) lines")
                                : nil,
                            // Read when tapped: the full log can be 1 MB.
                            copyAll: { display.full.map(\.text).joined() },
                            content: Text(ClaudeCodeBlock.attributedText(visible)))
                            .safeAreaInset(edge: .bottom) {
                                if hasMore {
                                    VStack(spacing: 0) {
                                        ClaudeDivider()
                                        Button("Show more", action: showMore)
                                            .font(.paseo(.callout))
                                            .foregroundStyle(Palette.ink)
                                            .frame(maxWidth: .infinity, minHeight: Metrics.hitSize)
                                            .contentShape(.rect)
                                            .accessibilityHint("Shows older lines of the output")
                                    }
                                    .background(Palette.panel)
                                }
                            }
                    }
            }
        }
    }

    /// Opens the sheet on its first page. A sheet closed after "Show more" reopens at the first
    /// page too, not at the size it had grown to.
    private func openSheet() {
        sheetCap = Self.sheetFirstLines
        showAll = true
    }

    /// One more page of the sheet's last lines.
    private func showMore() {
        sheetCap += Self.sheetStepLines
    }

    /// The UTF-8 length of `runs`, summed per run: O(runs), with no string work.
    private static func byteCount(_ runs: [AnsiRun]) -> Int {
        runs.reduce(0) { $0 + $1.text.utf8.count }
    }
}
#endif
