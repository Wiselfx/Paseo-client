#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// How a PR check's free-form status reads: passing, failing, or still running (anything else).
enum PRCheckStatus {
    static func isPassing(_ status: String?) -> Bool {
        switch status?.lowercased() {
        case "success", "passed", "pass", "neutral", "skipped": return true
        default: return false
        }
    }

    static func isFailing(_ status: String?) -> Bool {
        switch status?.lowercased() {
        case "failure", "failed", "fail", "error", "cancelled", "canceled", "timed_out", "timedout",
            "startup_failure", "stale": return true
        default: return false
        }
    }

    /// "2 failing · 1 running · 9 passed", or nil with no checks.
    static func rollup(_ checks: [CheckoutPrCheck]) -> String? {
        guard !checks.isEmpty else { return nil }
        let failing = checks.count(where: { isFailing($0.status) })
        let passing = checks.count(where: { isPassing($0.status) })
        let pending = checks.count - failing - passing
        var parts: [String] = []
        if failing > 0 { parts.append("\(failing) failing") }
        if pending > 0 { parts.append("\(pending) running") }
        if passing > 0 { parts.append("\(passing) passed") }
        return parts.joined(separator: " · ")
    }
}
#endif
