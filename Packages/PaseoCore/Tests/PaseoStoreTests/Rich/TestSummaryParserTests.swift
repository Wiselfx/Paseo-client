import Foundation
import Testing

@testable import PaseoStore

// G8 C12: runner summary recognition. Every fixture is modeled on real output and
// scrubbed (synthetic suites, paths and durations; no hostnames or user data).
struct TestSummaryParserTests {
    @Test("XCTest executed line")
    func xcTest() {
        let out = "Test Suite 'All tests' passed at 2026-01-01 00:00:00.\n\t Executed 128 tests, with 2 failures (0 unexpected) in 1.234 seconds\n"
        #expect(TestSummaryParser.parse(out) == TestSummary(passed: 126, failed: 2, skipped: 0))
    }

    @Test("swift-testing pass and fail lines")
    func swiftTesting() {
        #expect(TestSummaryParser.parse("✔ Test run with 128 tests in 5 suites passed after 0.001 seconds.\n")
            == TestSummary(passed: 128, failed: 0, skipped: 0))
        let failed = "✘ Test flaky() failed\n✘ Test other() failed\n✘ Test run with 10 tests in 1 suite failed after 0.001 seconds.\n"
        #expect(TestSummaryParser.parse(failed) == TestSummary(passed: 8, failed: 2, skipped: 0))
    }

    @Test("ANSI-wrapped output parses after stripping")
    func ansiWrapped() {
        let out = "\u{1B}[1m\u{1B}[32mTests:\u{1B}[0m       \u{1B}[31m2 failed\u{1B}[0m, 5 passed, 7 total\n"
        #expect(TestSummaryParser.parse(out) == TestSummary(passed: 5, failed: 2, skipped: 0))
    }

    @Test("Vitest pipe summary, either order")
    func vitest() {
        #expect(TestSummaryParser.parse("      Tests  2 failed | 5 passed (7)\n")
            == TestSummary(passed: 5, failed: 2, skipped: 0))
        #expect(TestSummaryParser.parse("      Tests  5 passed | 2 failed (7)\n")
            == TestSummary(passed: 5, failed: 2, skipped: 0))
    }

    @Test("pytest count line anchored on the duration")
    func pytest() {
        #expect(TestSummaryParser.parse("2 failed, 128 passed, 4 skipped in 12.34s\n")
            == TestSummary(passed: 128, failed: 2, skipped: 4))
        #expect(TestSummaryParser.parse("128 passed in 3.21s\n")
            == TestSummary(passed: 128, failed: 0, skipped: 0))
        // A failure list without the duration anchor is not a summary.
        #expect(TestSummaryParser.parse("FAILED example/test_x.py::test_y - assert 1 == 2\n") == nil)
    }

    @Test("cargo test result line")
    func cargo() {
        #expect(TestSummaryParser.parse("test result: FAILED. 126 passed; 2 failed; 4 ignored; 0 measured; 0 filtered out; finished in 1.23s\n")
            == TestSummary(passed: 126, failed: 2, skipped: 4))
        #expect(TestSummaryParser.parse("test result: ok. 10 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s\n")
            == TestSummary(passed: 10, failed: 0, skipped: 0))
    }

    @Test("go test failure lines, and no invented numbers on bare ok")
    func goTest() {
        let failed = "--- FAIL: TestWidget (0.00s)\n--- FAIL: TestGadget (0.00s)\nFAIL\n"
        #expect(TestSummaryParser.parse(failed) == TestSummary(passed: 0, failed: 2, skipped: 0))
        #expect(TestSummaryParser.parse("ok  \texample.com/widget\t1.234s\n") == nil)
    }

    @Test("chip copy follows the approved wording")
    func chipCopy() {
        #expect(TestSummary(passed: 128, failed: 2, skipped: 0).chipText == "128 passed · 2 failed")
        #expect(TestSummary(passed: 128, failed: 2, skipped: 4).chipText == "128 passed · 2 failed · 4 skipped")
    }

    @Test("unknown output yields no chip")
    func unknownYieldsNil() {
        #expect(TestSummaryParser.parse("BUILD SUCCEEDED\n") == nil)
        #expect(TestSummaryParser.parse("") == nil)
    }
}
