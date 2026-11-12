import Foundation

// MARK: - TestSummaryParser (G8 C12)

// NOTE: RemoteImagePipeline/G8: the compact chip next to the exit pill ("128 passed ·
// 2 failed") for known runner summaries. Parsed from ANSI-stripped output; runners are
// matched by their summary lines, never by prompt text, so unknown runners simply get
// no chip instead of a wrong one.

/// A parsed runner summary. `hasSummary` is false when the output carries no
/// recognizable summary (an `ok` without counts, an unknown runner): the card then
/// shows the exit pill alone instead of inventing numbers.
public struct TestSummary: Sendable, Equatable {
    public var passed: Int
    public var failed: Int
    public var skipped: Int
    public var hasSummary: Bool

    public init(passed: Int, failed: Int, skipped: Int, hasSummary: Bool = true) {
        self.passed = passed
        self.failed = failed
        self.skipped = skipped
        self.hasSummary = hasSummary
    }

    /// "128 passed · 2 failed" (plus " · 4 skipped" when nonzero) — the approved chip
    /// copy (§15).
    public var chipText: String {
        var text = "\(passed) passed · \(failed) failed"
        if skipped > 0 {
            text += " · \(skipped) skipped"
        }
        return text
    }
}

/// Recognizes the summary lines of the runners coding agents actually emit: swift
/// test/XCTest, Jest/Vitest, pytest, cargo test, go test. Tested against captured
/// (scrubbed) outputs.
public enum TestSummaryParser {
    public static func parse(_ output: String) -> TestSummary? {
        let text = AnsiText.plainText(output)
        if let summary = parseSwiftTest(text) { return summary }
        if let summary = parseJestVitest(text) { return summary }
        if let summary = parsePytest(text) { return summary }
        if let summary = parseCargo(text) { return summary }
        if let summary = parseGoTest(text) { return summary }
        return nil
    }

    // MARK: Runners

    /// XCTest: `Executed 128 tests, with 2 failures (0 unexpected) in 1.234 seconds`.
    /// swift-testing: `Test run with 128 tests in 5 suites passed after …`; on failure
    /// the count comes from the `✘`-marked test lines (best effort).
    private static func parseSwiftTest(_ text: String) -> TestSummary? {
        if let match = text.firstMatch(of: /Executed (\d+) tests?, with (\d+) failures?/) {
            let total = Int(match.output.1) ?? 0
            let failed = Int(match.output.2) ?? 0
            var skipped = 0
            if let skippedMatch = text.firstMatch(of: /with (\d+) skipped/),
                let count = Int(skippedMatch.output.1)
            {
                skipped = count
            }
            return TestSummary(passed: max(total - failed, 0), failed: failed, skipped: skipped)
        }
        if let match = text.firstMatch(of: /Test run with (\d+) tests? in \d+ suites? (\w+)/) {
            let total = Int(match.output.1) ?? 0
            guard String(match.output.2) == "passed" || String(match.output.2) == "failed" else {
                return nil
            }
            if String(match.output.2) == "passed" {
                return TestSummary(passed: total, failed: 0, skipped: 0)
            }
            // The summary line itself starts with ✘: count test lines, not it.
            let failed = text.split(separator: "\n").filter {
                $0.hasPrefix("✘ ") && !$0.contains("Test run with")
            }.count
            return TestSummary(passed: max(total - failed, 0), failed: failed, skipped: 0)
        }
        return nil
    }

    /// Jest `Tests: 2 failed, 5 passed, 7 total`; Vitest `Tests  2 failed | 5 passed`
    /// (either order, comma or pipe separated).
    private static func parseJestVitest(_ text: String) -> TestSummary? {
        for line in text.split(separator: "\n") {
            let lower = line.lowercased()
            guard lower.contains("tests") else { continue }
            let failed = firstInt(before: "failed", in: lower)
            let passed = firstInt(before: "passed", in: lower)
            let skipped = firstInt(before: "skipped", in: lower) ?? firstInt(before: "todo", in: lower)
            if failed != nil || passed != nil {
                return TestSummary(
                    passed: passed ?? 0, failed: failed ?? 0, skipped: skipped ?? 0)
            }
        }
        return nil
    }

    /// pytest: `2 failed, 128 passed, 4 skipped in 12.34s` (any subset, anchored on the
    /// trailing duration so failure lists don't match). Cargo's `test result:` lines
    /// end the same way, so they are excluded explicitly and left to their own parser.
    private static func parsePytest(_ text: String) -> TestSummary? {
        for line in text.split(separator: "\n") {
            let lower = String(line).lowercased()
            guard lower.contains(" in "), !lower.hasPrefix("test result:"),
                lower.range(of: #"\d+(\.\d+)?s$"#, options: .regularExpression) != nil
            else {
                continue
            }
            let failed = firstInt(before: "failed", in: lower)
            let passed = firstInt(before: "passed", in: lower)
            let skipped = firstInt(before: "skipped", in: lower)
                ?? firstInt(before: "deselected", in: lower)
            if failed != nil || passed != nil {
                return TestSummary(
                    passed: passed ?? 0, failed: failed ?? 0, skipped: skipped ?? 0)
            }
        }
        return nil
    }

    /// cargo: `test result: ok. 128 passed; 2 failed; 4 ignored; 0 measured; …`.
    private static func parseCargo(_ text: String) -> TestSummary? {
        guard let match = text.firstMatch(of: /test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored/) else {
            return nil
        }
        return TestSummary(
            passed: Int(match.output.2) ?? 0, failed: Int(match.output.3) ?? 0,
            skipped: Int(match.output.4) ?? 0)
    }

    /// go test: `--- FAIL:` lines count failures; a bare `ok` carries no counts, so an
    /// ok run without `-v` yields no chip rather than invented numbers.
    private static func parseGoTest(_ text: String) -> TestSummary? {
        let failed = text.split(separator: "\n").filter {
            $0.hasPrefix("--- FAIL:")
        }.count
        guard failed > 0 else { return nil }
        return TestSummary(passed: 0, failed: failed, skipped: 0)
    }

    /// The integer immediately before a keyword (`2 failed`, `128 passed`).
    /// Separators between the number and the word (usually one space) are skipped.
    /// Matched from the end: status words can contain the keyword (`FAILED.`).
    private static func firstInt(before keyword: String, in line: String) -> Int? {
        guard let range = line.range(of: keyword, options: .backwards) else { return nil }
        let tail = line[..<range.lowerBound].reversed().drop(while: { !$0.isNumber })
        let digits = String(tail.prefix(while: { $0.isNumber }).reversed())
        return Int(digits)
    }
}
