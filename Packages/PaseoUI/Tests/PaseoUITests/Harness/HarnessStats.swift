import Foundation

/// Numbers over one or more passes.
struct HarnessStats {
    var passes = 0
    var steps = 0
    var jumpsOnScreen = 0
    var jumpsOverscan = 0
    var sumAbsMotionOnScreen = 0.0
    var maxAbsMotionOnScreen = 0.0
    var sumAbsMotionOverscan = 0.0
    var maxAbsMotionOverscan = 0.0
    /// Row motion inside cells (where the SwiftUI content is drawn), on screen.
    var rowJumpsOnScreen = 0
    var sumAbsRowMotionOnScreen = 0.0
    var maxAbsRowMotionOnScreen = 0.0
    /// By gap kind ("rows", "ink").
    struct GapStats {
        var samples = 0
        var driftsOnScreen = 0
        var sumAbsDrift = 0.0
        var maxAbsDrift = 0.0
        var pairs = 0
        var pairsThatMoved = 0
        var maxRange = 0.0
        var json: [String: Any] {
            [
                "samples": samples, "driftsOnScreen": driftsOnScreen, "sumAbsDrift": sumAbsDrift,
                "maxAbsDrift": maxAbsDrift, "pairs": pairs, "pairsThatMoved": pairsThatMoved,
                "maxRange": maxRange,
            ]
        }
    }
    var gapStats: [String: GapStats] = ["rows": GapStats(), "ink": GapStats()]
    /// Ink edges of cells (where pixels are drawn) moving beyond the scroll, on screen.
    var inkJumpsOnScreen = 0
    var sumAbsInkMotionOnScreen = 0.0
    var maxAbsInkMotionOnScreen = 0.0
    var inkSamples = 0
    var inkMissing = 0
    var inflatedFrames = 0
    var cellsSeen = 0
    var maxInflation = 0.0
    var sumInflation = 0.0
    var slackItems = 0
    var slackItemsThatMoved = 0
    var maxSlackRange = 0.0
    var inkTopItemsThatMoved = 0
    var maxInkTopRange = 0.0
    /// Mismatch samples split by whether the cell content view had a safe area inset.
    var mismatchWithSafeInset = 0
    var mismatchWithoutSafeInset = 0
    var mismatchSamples = 0
    var mismatchSamplesOnScreen = 0
    var mismatchOnScreen = 0
    var mismatchMaxOnScreen = 0.0
    var mismatchAll = 0
    var mismatchMaxAll = 0.0
    var mismatchAtRest = 0
    var mismatchMaxAtRest = 0.0
    var firstMeasures = 0
    var estimateMeanAbs = 0.0
    var estimateMaxAbs = 0.0
    /// Mean of (estimate - measured): negative means estimates run short.
    var estimateMeanSigned = 0.0
    var invalidations = 0
    var invalidationsCompensated = 0
    var invalidationsByBranch: [String: Int] = [:]
    var invalidationsByPosition: [String: Int] = [:]
    var invalidationsByBranchAndPosition: [String: Int] = [:]
    var offsetWritesBySite: [String: Int] = [:]
    var dequeues = 0
    var dequeuesUnmeasured = 0

    @MainActor
    init(_ passes: [PassData]) {
        self.passes = passes.count
        var estimateAbsSum = 0.0
        var estimateSignedSum = 0.0
        for pass in passes {
            steps += pass.steps.count
            for jump in pass.jumps where jump.kind == "row" || jump.kind.hasPrefix("ink") {
                guard jump.onScreen else { continue }
                if jump.kind == "row" {
                    rowJumpsOnScreen += 1
                    sumAbsRowMotionOnScreen += abs(jump.amount)
                    maxAbsRowMotionOnScreen = max(maxAbsRowMotionOnScreen, abs(jump.amount))
                } else {
                    inkJumpsOnScreen += 1
                    sumAbsInkMotionOnScreen += abs(jump.amount)
                    maxAbsInkMotionOnScreen = max(maxAbsInkMotionOnScreen, abs(jump.amount))
                }
            }
            for (kind, count) in pass.gapSampleCounts { gapStats[kind, default: GapStats()].samples += count }
            for gap in pass.gaps where gap.onScreen {
                gapStats[gap.kind, default: GapStats()].driftsOnScreen += 1
                gapStats[gap.kind, default: GapStats()].sumAbsDrift += abs(gap.drift)
                gapStats[gap.kind, default: GapStats()].maxAbsDrift =
                    max(gapStats[gap.kind]?.maxAbsDrift ?? 0, abs(gap.drift))
            }
            for range in pass.gapRanges.values {
                gapStats[range.kind, default: GapStats()].pairs += 1
                let threshold = range.kind == "ink" ? 1.5 : 0.5
                if range.range > threshold { gapStats[range.kind, default: GapStats()].pairsThatMoved += 1 }
                gapStats[range.kind, default: GapStats()].maxRange =
                    max(gapStats[range.kind]?.maxRange ?? 0, range.range)
            }
            inkSamples += pass.inkAvailableSamples
            inkMissing += pass.inkMissingSamples
            for (_, value) in pass.inflation {
                cellsSeen += 1
                sumInflation += value
                maxInflation = max(maxInflation, value)
                if value > 0.5 { inflatedFrames += 1 }
            }
            for (_, range) in pass.bottomSlack {
                slackItems += 1
                maxSlackRange = max(maxSlackRange, range.max - range.min)
                if range.max - range.min > 1.5 { slackItemsThatMoved += 1 }
            }
            for (_, range) in pass.inkTopRange {
                maxInkTopRange = max(maxInkTopRange, range.max - range.min)
                if range.max - range.min > 1.5 { inkTopItemsThatMoved += 1 }
            }
            for jump in pass.jumps where jump.kind == "cell" {
                let amount = abs(jump.amount)
                if jump.onScreen {
                    jumpsOnScreen += 1
                    sumAbsMotionOnScreen += amount
                    maxAbsMotionOnScreen = max(maxAbsMotionOnScreen, amount)
                } else {
                    jumpsOverscan += 1
                    sumAbsMotionOverscan += amount
                    maxAbsMotionOverscan = max(maxAbsMotionOverscan, amount)
                }
            }
            mismatchSamples += pass.mismatchSamples
            mismatchSamplesOnScreen += pass.mismatchSamplesOnScreen
            for record in pass.mismatches {
                let size = abs(record.mismatch)
                mismatchAll += 1
                mismatchMaxAll = max(mismatchMaxAll, size)
                if record.onScreen {
                    mismatchOnScreen += 1
                    mismatchMaxOnScreen = max(mismatchMaxOnScreen, size)
                }
                if record.safeTop + record.safeBottom > 0.5 {
                    mismatchWithSafeInset += 1
                } else {
                    mismatchWithoutSafeInset += 1
                }
                if record.atRest {
                    mismatchAtRest += 1
                    mismatchMaxAtRest = max(mismatchMaxAtRest, size)
                }
            }
            for record in pass.invalidations {
                invalidations += 1
                if record.compensated { invalidationsCompensated += 1 }
                invalidationsByBranch[record.branch, default: 0] += 1
                invalidationsByPosition[record.position, default: 0] += 1
                invalidationsByBranchAndPosition["\(record.branch)/\(record.position)", default: 0] += 1
                if record.firstMeasure {
                    firstMeasures += 1
                    let error = record.oldHeight - record.newHeight
                    estimateAbsSum += abs(error)
                    estimateSignedSum += error
                    estimateMaxAbs = max(estimateMaxAbs, abs(error))
                }
            }
            for write in pass.offsetWrites { offsetWritesBySite[write.site, default: 0] += 1 }
            dequeues += pass.dequeues.count
            dequeuesUnmeasured += pass.dequeues.filter { !$0.hadMeasured }.count
        }
        if firstMeasures > 0 {
            estimateMeanAbs = estimateAbsSum / Double(firstMeasures)
            estimateMeanSigned = estimateSignedSum / Double(firstMeasures)
        }
    }

    var json: [String: Any] {
        [
            "passes": passes, "steps": steps,
            "jumpsOnScreen": jumpsOnScreen, "jumpsOverscan": jumpsOverscan,
            "sumAbsMotionOnScreen": sumAbsMotionOnScreen, "maxAbsMotionOnScreen": maxAbsMotionOnScreen,
            "sumAbsMotionOverscan": sumAbsMotionOverscan, "maxAbsMotionOverscan": maxAbsMotionOverscan,
            "rowJumpsOnScreen": rowJumpsOnScreen, "sumAbsRowMotionOnScreen": sumAbsRowMotionOnScreen,
            "maxAbsRowMotionOnScreen": maxAbsRowMotionOnScreen,
            "gap": gapStats.mapValues { $0.json },
            "inkJumpsOnScreen": inkJumpsOnScreen, "sumAbsInkMotionOnScreen": sumAbsInkMotionOnScreen,
            "maxAbsInkMotionOnScreen": maxAbsInkMotionOnScreen, "inkSamples": inkSamples,
            "inkMissing": inkMissing, "framesInflatedBySafeArea": inflatedFrames, "cellsSeen": cellsSeen,
            "maxInflation": maxInflation, "sumInflation": sumInflation, "slackItems": slackItems,
            "slackItemsThatMoved": slackItemsThatMoved, "maxSlackRange": maxSlackRange,
            "inkTopItemsThatMoved": inkTopItemsThatMoved, "maxInkTopRange": maxInkTopRange,
            "mismatchWithSafeInset": mismatchWithSafeInset,
            "mismatchWithoutSafeInset": mismatchWithoutSafeInset,
            "mismatchSamples": mismatchSamples, "mismatchSamplesOnScreen": mismatchSamplesOnScreen,
            "mismatchOnScreen": mismatchOnScreen, "mismatchMaxOnScreen": mismatchMaxOnScreen,
            "mismatchAll": mismatchAll, "mismatchMaxAll": mismatchMaxAll,
            "mismatchAtRest": mismatchAtRest, "mismatchMaxAtRest": mismatchMaxAtRest,
            "firstMeasures": firstMeasures, "estimateMeanAbs": estimateMeanAbs,
            "estimateMaxAbs": estimateMaxAbs, "estimateMeanSigned": estimateMeanSigned,
            "invalidations": invalidations, "invalidationsCompensated": invalidationsCompensated,
            "invalidationsByBranch": invalidationsByBranch,
            "invalidationsByPosition": invalidationsByPosition,
            "invalidationsByBranchAndPosition": invalidationsByBranchAndPosition,
            "offsetWritesBySite": offsetWritesBySite,
            "dequeues": dequeues, "dequeuesUnmeasured": dequeuesUnmeasured,
        ]
    }
}
