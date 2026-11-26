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
            for jump in pass.jumps {
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
