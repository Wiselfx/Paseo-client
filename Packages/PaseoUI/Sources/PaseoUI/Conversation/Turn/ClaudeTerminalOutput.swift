#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The tail in ANSI colors, with "Show all" opening the capped sheet. Until the
/// first parse lands, the plain last 12 lines hold the final box height and only
/// the colors change — no jump, no repeated work on remount.
struct ClaudeTerminalOutput: View {
    let output: String
    /// The parse `ClaudeCodeBlock` holds; nil until the first one lands.
    let parsed: ClaudeCodeBlock.ParsedTerminal?

    @State private var showAll = false

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
                Button("Show all \(PaseoFormat.integer(display.lineCount)) lines") { showAll = true }
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(minHeight: Metrics.hitSize)
                    .accessibilityHint("Opens the full terminal output")
                    .sheet(isPresented: $showAll) {
                        OutputSheet(
                            note: display.lineCount > ClaudeCodeBlock.sheetLines
                                ? Text(
                                    "Showing the last \(PaseoFormat.integer(ClaudeCodeBlock.sheetLines)) of \(PaseoFormat.integer(display.lineCount)) lines")
                                : nil,
                            // Read when tapped: the full log can be 1 MB.
                            copyAll: { display.full.map(\.text).joined() },
                            content: Text(display.sheetAttributed))
                    }
            }
        }
    }
}
#endif
