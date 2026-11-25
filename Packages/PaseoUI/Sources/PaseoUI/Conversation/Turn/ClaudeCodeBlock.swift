#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Terminal-style output: an optional command line, then output that scrolls both ways inside a
/// capped height, so a 2,000-line log never takes over the conversation.
struct ClaudeCodeBlock: View {
    var title: String?
    var command: String?
    var output: String?
    var status: ToolCallPresentation.Status
    var maxHeight: CGFloat
    /// Terminal mode (G8 C12): ANSI colors, a 12-line tail, the exit pill and the
    /// test chip. Parses off main, once per output (never per body pass).
    var terminal: Bool = false
    /// The shell exit code, for the exit pill. Nil when the call never reported one.
    var exitCode: Double? = nil

    /// The parsed terminal: tail runs for the card, full runs for Copy all, the
    /// capped sheet runs for Show all, the test summary for the chip, and the total
    /// line count for the Show-all label. The sheet's `AttributedString` is not here:
    /// it builds when Show all presents the sheet (a SwiftUI `Text` with 1 MB of
    /// `AttributedString` is very slow, and a streaming command would rebuild it on
    /// every chunk for a sheet nobody has opened).
    struct ParsedTerminal: Equatable {
        var tail: [AnsiRun]
        var full: [AnsiRun]
        /// The last `sheetLines` lines' runs; the sheet lays out only the tail of these.
        var sheet: [AnsiRun]
        /// The tail's coloured text, built once per parse.
        var tailAttributed: AttributedString
        var summary: TestSummary?
        var lineCount: Int
    }

    @State private var parsed: ParsedTerminal?

    /// The sheet's line cap (G8 review): the parse keeps at most this many lines for the sheet.
    /// `ClaudeTerminalOutput` lays out the last of them, from a first page of 200 that grows on request.
    nonisolated static let sheetLines = 2000

    init(
        title: String? = nil, command: String? = nil, output: String?,
        status: ToolCallPresentation.Status = .succeeded, maxHeight: CGFloat = 260,
        terminal: Bool = false, exitCode: Double? = nil
    ) {
        self.title = title
        self.command = command
        self.output = output
        self.status = status
        self.maxHeight = maxHeight
        self.terminal = terminal
        self.exitCode = exitCode
    }

    /// The last 12 lines: the tail that carries the verdict (G8 C12).
    nonisolated static let tailLines = 12

    private var copyText: String {
        if let parsed {
            return parsed.full.map(\.text).joined()
        }
        return [command, output].compactMap { $0 }.joined(separator: "\n")
    }

    /// Exit code as a StatePill: quiet success for 0, failure ink otherwise (G8 C12).
    @ViewBuilder private var exitPill: some View {
        if let exitCode {
            let code = Int(exitCode)
            StatePill("Exit \(code)", tone: code == 0 ? .success : .failure)
        }
    }

    /// The test chip: "{passed} passed · {failed} failed" when a known runner's
    /// summary parsed, nothing otherwise (never an invented count).
    @ViewBuilder private var testChip: some View {
        if let summary = parsed?.summary, summary.hasSummary {
            StatePill(summary.chipText, tone: summary.failed > 0 ? .failure : .success)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if command != nil || title != nil || terminal {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ClaudeStatusDot(status: status)
                    if let title {
                        Text(title).font(.paseo(.codeSmall)).foregroundStyle(
                            Palette.secondaryInk)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    if let command {
                        Text(command).font(.paseo(.codeSmall)).foregroundStyle(
                            Palette.ink
                        ).lineLimit(3)
                    }
                    Spacer(minLength: 8)
                    testChip
                    exitPill
                    ClaudeCopyButton(text: copyText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                if hasOutput { ClaudeDivider() }
            }
            if hasOutput {
                if terminal, let output {
                    ClaudeTerminalOutput(output: output, parsed: parsed)
                } else if let output {
                    // The first lines, sideways-scrollable; the rest a tap away. A whole file laid
                    // out in a capped scroll box cost its full text layout on every measure.
                    ClaudeOutputPreview(text: output, maxLines: max(4, Int(maxHeight / 17)))
                }
            }
        }
        .task(id: terminal ? output : nil) { await parseTerminal() }
        .background(Palette.codeSurface, in: .rect(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.cardBorder, lineWidth: 1)
        }
        .codeTypeScale()
    }

    /// Parses the output off main when it changes (never per body pass): ANSI runs,
    /// the tail slice, the capped sheet slice, and the test summary. The tail's
    /// `AttributedString` builds once here and rides with the parse into the cache.
    /// The sheet's string is left to Show all, so a streaming command does not build
    /// up to 2,000 lines of color on every chunk for a sheet nobody has opened.
    /// State writes only when the output changes.
    @MainActor
    private func parseTerminal() async {
        guard terminal, let output, !output.isEmpty else {
            parsed = nil
            return
        }
        if let cached = TerminalParseCache.entry(for: output) {
            parsed = cached
            return
        }
        // The parse runs off main; the tail's AttributedString (fonts and colours are
        // main-actor tokens) is built here, from the 12 tail lines only.
        guard let parts = await Self.parseParts(output), !Task.isCancelled else { return }
        let result = ParsedTerminal(
            tail: parts.tail, full: parts.full, sheet: parts.sheet,
            tailAttributed: Self.attributedText(parts.tail), summary: parts.summary,
            lineCount: parts.lines)
        TerminalParseCache.store(result, for: output)
        parsed = result
    }

    /// The off-main half of the parse. `@concurrent` runs it on the global pool as a child of the
    /// caller's task, so cancelling `.task(id:)` reaches it; the parse itself is synchronous, so it
    /// is checked between steps and a superseded output stops there (nil) instead of finishing a
    /// parse nobody will read.
    @concurrent nonisolated private static func parseParts(_ output: String) async -> (
        tail: [AnsiRun], full: [AnsiRun], sheet: [AnsiRun], summary: TestSummary?, lines: Int
    )? {
        let runs = AnsiText.parse(output)
        if Task.isCancelled { return nil }
        let tail = AnsiText.tail(runs, maxLines: tailLines)
        let sheet = AnsiText.tail(runs, maxLines: sheetLines)
        if Task.isCancelled { return nil }
        let summary = TestSummaryParser.parse(output)
        let lines = runs.reduce(0) { $0 + $1.text.count(where: \.isNewline) }
        return (tail, runs, sheet, summary, lines)
    }

    /// Runs to a colored `AttributedString`, on the main actor (fonts and colors are main-actor
    /// tokens). The tail builds once per parse; the sheet builds when Show all presents it.
    static func attributedText(_ runs: [AnsiRun]) -> AttributedString {
        var out = AttributedString()
        for run in runs {
            var part = AttributedString(run.text)
            part.font = .paseo(.codeSmall)
            if run.style.bold { part.font = part.font?.bold() }
            if let foreground = run.style.foreground {
                part.foregroundColor = Palette.ansi(foreground)
            } else {
                part.foregroundColor = Palette.ink.opacity(0.85)
            }
            if run.style.dim, let color = part.foregroundColor {
                part.foregroundColor = color.opacity(0.65)
            }
            if let background = run.style.background {
                part.backgroundColor = Palette.ansi(background)
            }
            if run.style.underline { part.underlineStyle = .single }
            if run.style.strikethrough { part.strikethroughStyle = .single }
            out += part
        }
        return out
    }

    private var hasOutput: Bool { !(output ?? "").isEmpty }
}
#endif
