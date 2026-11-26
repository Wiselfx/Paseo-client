import CoreGraphics
import Foundation

/// Raw events of one pass. Each has a `json` form for report.json.
struct InvalidationRecord {
    var step: Int
    var item: String
    var index: Int
    var oldHeight: Double
    var newHeight: Double
    var firstMeasure: Bool
    var compensated: Bool
    var branch: String
    /// Where the cell sat relative to the reader's line: above, straddling or below.
    var position: String
    var frameMinY: Double
    var frameMaxY: Double
    var readerTop: Double

    var delta: Double { newHeight - oldHeight }

    var json: [String: Any] {
        [
            "step": step, "item": item, "index": index, "old": oldHeight, "new": newHeight, "delta": delta,
            "firstMeasure": firstMeasure, "compensated": compensated, "branch": branch, "position": position,
            "frameMinY": frameMinY, "frameMaxY": frameMaxY, "readerTop": readerTop,
        ]
    }

    var summary: String {
        "invalidation \(item) \(String(format: "%.1f", oldHeight))->\(String(format: "%.1f", newHeight)) "
            + "(delta \(String(format: "%+.1f", delta))) \(position) branch=\(branch) "
            + "compensated=\(compensated) first=\(firstMeasure)"
    }
}

struct OffsetWriteRecord {
    var step: Int
    var site: String
    var from: Double
    var to: Double

    var json: [String: Any] { ["step": step, "site": site, "from": from, "to": to] }
    var summary: String {
        "offset write \(site) \(String(format: "%.1f", from))->\(String(format: "%.1f", to))"
    }
}

struct DequeueRecord {
    var step: Int
    var item: String
    var index: Int
    var hadMeasured: Bool
    var height: Double

    var json: [String: Any] {
        ["step": step, "item": item, "index": index, "hadMeasured": hadMeasured, "layoutHeight": height]
    }
}

struct StepRecord {
    var step: Int
    var requestedOffset: Double
    var actualOffset: Double
    var visibleCells: Int
    var onScreenCells: Int

    var json: [String: Any] {
        [
            "step": step, "requestedOffset": requestedOffset, "actualOffset": actualOffset,
            "visibleCells": visibleCells, "onScreenCells": onScreenCells,
        ]
    }
}

struct JumpRecord {
    var step: Int
    var item: String
    var amount: Double
    var screenYPrevious: Double
    var screenYNow: Double
    var commandedMotion: Double
    var onScreen: Bool
    /// What happened in the step: the invalidations and engine offset writes recorded during it.
    var context: [String]

    var json: [String: Any] {
        [
            "step": step, "item": item, "unexplainedMotion": amount, "screenYPrevious": screenYPrevious,
            "screenYNow": screenYNow, "commandedMotion": commandedMotion, "onScreen": onScreen,
            "context": context,
        ]
    }
}

struct MismatchRecord {
    var step: Int
    var item: String
    var cellHeight: Double
    var drawnHeight: Double
    var onScreen: Bool
    var atRest: Bool

    var mismatch: Double { cellHeight - drawnHeight }

    var json: [String: Any] {
        [
            "step": step, "item": item, "cellHeight": cellHeight, "drawnHeight": drawnHeight,
            "mismatch": mismatch, "onScreen": onScreen, "atRest": atRest,
        ]
    }
}
