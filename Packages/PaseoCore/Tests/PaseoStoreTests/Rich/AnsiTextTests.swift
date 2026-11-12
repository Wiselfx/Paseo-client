import Foundation
import Testing

@testable import PaseoStore

// G8 C12: SGR parsing, tail truncation and the copy path. Fixtures are modeled on real
// runner output and scrubbed (example.com, synthetic paths, no user data).
struct AnsiTextTests {
    @Test("plain text passes through as one run")
    func plainTextPassesThrough() {
        #expect(AnsiText.parse("hello world\n") == [AnsiRun(text: "hello world\n", style: .plain)])
    }

    @Test("SGR colors attach to the following text and reset clears")
    func sgrColorsAttachAndReset() {
        let runs = AnsiText.parse("\u{1B}[31mFAILED\u{1B}[0m ok\n")
        #expect(runs.count == 2)
        #expect(runs[0].style.foreground == .red)
        #expect(runs[0].text == "FAILED")
        #expect(runs[1] == AnsiRun(text: " ok\n", style: .plain))
    }

    @Test("bold, bright and 256-color sequences map into the 16")
    func emphasisAndExtendedColors() {
        let runs = AnsiText.parse("\u{1B}[1;93mWARN\u{1B}[0m \u{1B}[38;5;196mred-ish\u{1B}[0m \u{1B}[38;2;10;200;10mgreen-ish\u{1B}[0m\n")
        // The trailing newline is its own plain run: resets end the styled run.
        #expect(runs.count == 6)
        #expect(runs[0].style == AnsiStyle(foreground: .brightYellow, bold: true))
        #expect(runs[2].style.foreground == .red)
        #expect(runs[4].style.foreground == .green)
        #expect(runs[5] == AnsiRun(text: "\n", style: .plain))
    }

    @Test("cursor movement and erasing are dropped, text stays")
    func cursorMovementDropped() {
        #expect(AnsiText.parse("50%\u{1B}[2K\u{1B}[Gdone\n").map(\.text).joined() == "50%done\n")
        // The sweep is display text; the erase leaves only the final write.
        #expect(AnsiText.plainText("\u{1B}[1A\u{1B}[2Kpass\n") == "pass\n")
    }

    @Test("carriage returns resolve progress lines to their final write")
    func carriageReturnsResolve() {
        #expect(AnsiText.plainText("building 50%\rbuilding 100%\n") == "building 100%\n")
    }

    @Test("unknown SGR codes are ignored, not fatal")
    func unknownCodesIgnored() {
        let runs = AnsiText.parse("\u{1B}[999mkept\u{1B}[0m\n")
        #expect(runs.map(\.text).joined() == "kept\n")
    }

    @Test("a bare reset-only fence is equivalent to plain")
    func bareResetIsPlain() {
        #expect(AnsiText.parse("\u{1B}[mok\n") == [AnsiRun(text: "ok\n", style: .plain)])
    }

    @Test("copy text never carries escapes")
    func copyTextIsClean() {
        #expect(AnsiText.plainText("\u{1B}[32mok\u{1B}[0m \u{1B}]8;;https://example.com\u{1B}\\link\u{1B}]8;;\u{1B}\\") == "ok link")
    }

    @Test("tail keeps the last N lines with their styles")
    func tailKeepsLastLines() {
        let runs = AnsiText.parse("one\n\u{1B}[31mtwo\u{1B}[0m\nthree\nfour\n")
        let tail = AnsiText.tail(runs, maxLines: 2)
        #expect(tail.map(\.text).joined() == "three\nfour\n")
        #expect(tail.allSatisfy { $0.style == .plain })
        let colored = AnsiText.tail(runs, maxLines: 3)
        #expect(colored.map(\.text).joined() == "two\nthree\nfour\n")
        #expect(colored.first?.style.foreground == .red)
    }

    /// The cheap tail matches the parsed tail line-for-line (the placeholder shows
    /// what the parse will show, at the same height).
    @Test("plain tail matches parsed tail")
    func plainTailMatchesParsedTail() {
        let lines = (1...30).map { "line \($0)" }
        let input = lines.joined(separator: "\n") + "\n"
        let colored = lines.enumerated().map { index, line in
            "\u{1B}[3\(index % 8)m" + line + "\u{1B}[0m"
        }.joined(separator: "\n") + "\n"
        #expect(AnsiText.plainTail(input, maxLines: 12) == AnsiText.tail(
            AnsiText.parse(input), maxLines: 12).map(\.text).joined())
        #expect(AnsiText.plainTail(colored, maxLines: 12) == AnsiText.tail(
            AnsiText.parse(colored), maxLines: 12).map(\.text).joined())
        #expect(AnsiText.plainTail("one\n", maxLines: 12) == "one\n")
        #expect(AnsiText.plainTail("", maxLines: 12) == "")
        #expect(AnsiText.plainTail("a\nb\nc", maxLines: 2) == "b\nc")
        #expect(AnsiText.plainTail("a\nb\nc\n", maxLines: 2) == "b\nc\n")
    }

    /// 1 MB of SGR-heavy output parses well under the 50 ms budget (G8 acceptance,
    /// measured on Linux CI; typical runs land an order of magnitude below).
    @Test("one megabyte parses in under 50 ms")
    func megabyteParsesFast() {
        var big = ""
        big.reserveCapacity(1_500_000)
        for index in 0..<20_000 {
            big += "\u{1B}[3\(index % 8)mline \(index) with some content to pad the bytes out a little\u{1B}[0m\n"
        }
        #expect(big.utf8.count > 1_000_000)
        let start = Date()
        let runs = AnsiText.parse(big)
        let elapsed = Date().timeIntervalSince(start)
        #expect(!runs.isEmpty)
        #expect(elapsed < 0.05, "1 MB parsed in \(elapsed)s")
    }
}
