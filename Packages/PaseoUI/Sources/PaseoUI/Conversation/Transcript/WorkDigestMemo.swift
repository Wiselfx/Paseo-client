#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The run's derived values, recomputed only when the run changes. Each thought's length is
/// parsed once.
@MainActor
final class WorkDigestMemo {
    private var group: Turn.WorkGroup?
    private var value = WorkDigestValue()
    private var knownDurations: [String: TimeInterval] = [:]

    func digest(for group: Turn.WorkGroup) -> WorkDigestValue {
        if let cached = self.group, cached == group { return value }
        self.group = group
        var digest = WorkDigestValue()
        let rows = group.rows
        var seconds: TimeInterval = 0
        var timed = false
        for (index, row) in rows.enumerated() {
            switch row.item {
            case .reasoning:
                digest.thoughts.append(row)
                guard index + 1 < rows.count else { continue }
                if let duration = duration(of: row, endingAt: rows[index + 1]) {
                    seconds += duration
                    timed = true
                }
            case .toolCall(let call):
                if call.status == .failed { digest.failures += 1 }
                if call.status == .running { digest.running = WorkToolWording(call) }
            default:
                break
            }
        }
        digest.thoughtSeconds = timed ? seconds : nil
        if case .reasoning = rows.last?.item { digest.endsInThought = true }
        digest.steps = WorkRow.merging(rows).filter {
            if case .thought = $0 { false } else { true }
        }
        digest.summary = WorkDigest.summaryText(group)
        value = digest
        return digest
    }

    private func duration(of row: TimelineRow, endingAt next: TimelineRow) -> TimeInterval? {
        if let known = knownDurations[row.id] { return known }
        guard let start = PaseoDate.parse(row.timestamp), let end = PaseoDate.parse(next.timestamp)
        else { return nil }
        let seconds = max(0, end.timeIntervalSince(start))
        knownDurations[row.id] = seconds
        return seconds
    }
}
#endif
