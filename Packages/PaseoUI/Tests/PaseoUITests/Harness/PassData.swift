import CoreGraphics
import Foundation

/// Everything one scroll pass recorded.
@MainActor
final class PassData {
    let scenario: String
    let name: String
    let stepSize: Double
    let mode: String

    /// -1 before the first step (settling), 1... during the pass, -2 after it (resting).
    var currentStep = -1
    var steps: [StepRecord] = []
    var invalidations: [InvalidationRecord] = []
    var offsetWrites: [OffsetWriteRecord] = []
    var dequeues: [DequeueRecord] = []
    var jumps: [JumpRecord] = []
    var mismatches: [MismatchRecord] = []
    var gaps: [GapRecord] = []
    var gapRanges: [String: GapRange] = [:]
    var gapSampleCounts: [String: Int] = [:]
    /// Per item: the largest (cell height - natural height) seen: how much the frame carries beyond what
    /// the content needs (safe area inflated at measure time).
    var inflation: [String: Double] = [:]
    /// Per item: min and max of (cell height - ink bottom) and of the ink top, in the cell's own space.
    var bottomSlack: [String: (min: Double, max: Double)] = [:]
    var inkTopRange: [String: (min: Double, max: Double)] = [:]
    var inkAvailableSamples = 0
    var inkMissingSamples = 0
    /// Compact per-step series of on-screen cells (for analysis; see `SampleRecord`).
    var samples: [SampleRecord] = []
    /// Cells sampled for mismatch (on screen and in the overscan), to read the counts against.
    var mismatchSamples = 0
    var mismatchSamplesOnScreen = 0
    var wallSeconds = 0.0

    init(scenario: String, name: String, stepSize: Double, mode: String) {
        self.scenario = scenario
        self.name = name
        self.stepSize = stepSize
        self.mode = mode
    }

    var title: String { "\(scenario)/\(name)" }

    func context(forStep step: Int) -> [String] {
        invalidations.filter { $0.step == step }.map(\.summary)
            + offsetWrites.filter { $0.step == step }.map(\.summary)
    }
}
