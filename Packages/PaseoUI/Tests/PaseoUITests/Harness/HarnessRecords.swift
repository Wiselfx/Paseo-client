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
    /// "cell" (the collection view's frame for the cell) or "row" (a SwiftUI row inside the cell, from
    /// the row anchors: where the content is drawn).
    var kind: String
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
            "step": step, "kind": kind, "item": item, "unexplainedMotion": amount, "screenYPrevious": screenYPrevious,
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
    /// The cell content view's safe area insets when sampled.
    var safeTop: Double = 0
    var safeBottom: Double = 0

    var mismatch: Double { cellHeight - drawnHeight }

    var json: [String: Any] {
        [
            "step": step, "item": item, "cellHeight": cellHeight, "drawnHeight": drawnHeight,
            "mismatch": mismatch, "onScreen": onScreen, "atRest": atRest, "safeTop": safeTop,
            "safeBottom": safeBottom,
        ]
    }
}

/// The visible gap between a turn's last row and the next turn's prompt changed between two steps.
struct GapRecord {
    var step: Int
    /// "rows" (from the SwiftUI row anchors) or "ink" (from the pixels the cell draws).
    var kind: String
    var upper: String
    var lower: String
    var previousGap: Double
    var gap: Double
    var onScreen: Bool

    var drift: Double { gap - previousGap }

    var json: [String: Any] {
        [
            "step": step, "kind": kind, "upper": upper, "lower": lower, "previousGap": previousGap,
            "gap": gap, "drift": drift, "onScreen": onScreen,
        ]
    }
}

/// One on-screen cell at one step, compact: the raw series behind the other records.
struct SampleRecord {
    var step: Int
    var item: String
    var screenY: Double
    var cellHeight: Double
    var drawnHeight: Double
    var safeTop: Double
    var safeBottom: Double
    var firstRowMinY: Double?
    var lastRowMaxY: Double?
    var inkTop: Double?
    var inkBottom: Double?

    var json: [Any] {
        [
            step, item, screenY, cellHeight, drawnHeight, safeTop, safeBottom,
            firstRowMinY ?? NSNull(), lastRowMaxY ?? NSNull(), inkTop ?? NSNull(), inkBottom ?? NSNull(),
        ]
    }
}

/// How far one adjacent pair's gap ranged over a pass.
struct GapRange {
    var kind: String
    var upper: String
    var lower: String
    var first: Double
    var minimum: Double
    var maximum: Double

    var range: Double { maximum - minimum }

    var json: [String: Any] {
        [
            "kind": kind, "upper": upper, "lower": lower, "first": first, "min": minimum, "max": maximum,
            "range": range,
        ]
    }
}
