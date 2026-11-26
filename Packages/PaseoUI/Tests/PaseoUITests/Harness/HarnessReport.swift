import Foundation

/// Builds report.md and report.json from the recorded passes.
@MainActor
enum HarnessReport {
    private static func f(_ value: Double) -> String { String(format: "%.2f", value) }

    private static func counts(_ dictionary: [String: Int]) -> String {
        if dictionary.isEmpty { return "none" }
        return dictionary.keys.sorted().map { "\($0)=\(dictionary[$0] ?? 0)" }.joined(separator: ", ")
    }

    /// Scenario names in the order they ran.
    private static func scenarios(_ passes: [PassData]) -> [String] {
        var seen: [String] = []
        for pass in passes where !seen.contains(pass.scenario) { seen.append(pass.scenario) }
        return seen
    }

    private static func statsBlock(_ title: String, _ passes: [PassData]) -> String {
        let s = HarnessStats(passes)
        var out = "### \(title)\n\n"
        out += "- steps: \(s.steps)\n"
        out +=
            "- JUMP events (|unexplained| > 0.5 pt) on screen: \(s.jumpsOnScreen); sum \(f(s.sumAbsMotionOnScreen)) pt; max \(f(s.maxAbsMotionOnScreen)) pt\n"
        out +=
            "- JUMP events in the overscan (not seen): \(s.jumpsOverscan); sum \(f(s.sumAbsMotionOverscan)) pt; max \(f(s.maxAbsMotionOverscan)) pt\n"
        out +=
            "- ROW motion on screen (content inside cells, |unexplained| > 0.5): \(s.rowJumpsOnScreen); sum \(f(s.sumAbsRowMotionOnScreen)) pt; max \(f(s.maxAbsRowMotionOnScreen)) pt\n"
        out +=
            "- DRAWN motion on screen (top and bottom of what each cell draws, |unexplained| > 1.5): \(s.inkJumpsOnScreen); sum \(f(s.sumAbsInkMotionOnScreen)) pt; max \(f(s.maxAbsInkMotionOnScreen)) pt "
            + "(\(s.inkSamples) cell samples with a drawn extent, \(s.inkMissing) without)\n"
        for kind in ["drawn", "rows"] {
            guard let g = s.gapStats[kind] else { continue }
            let what =
                kind == "drawn"
                ? "bottom of what a turn draws to the top of what the next turn draws (the gap you see)"
                : "last row anchor of a turn to the next turn's prompt anchor"
            out +=
                "- GAP \(kind) (\(what)): \(g.pairs) adjacent pairs seen, \(g.pairsThatMoved) changed by more than \(kind == "drawn" ? "1.5" : "0.5") pt (max range \(f(g.maxRange)) pt); "
                + "\(g.driftsOnScreen) step-to-step drifts on screen of \(g.samples) samples, sum \(f(g.sumAbsDrift)) pt, max \(f(g.maxAbsDrift)) pt\n"
        }
        out +=
            "- cell frames taller than the content needs (cell - natural height, natural = fitting minus safe area insets): \(s.inflatedFrames) of \(s.cellsSeen) cells; mean \(f(s.cellsSeen > 0 ? s.sumInflation / Double(s.cellsSeen) : 0)) pt, max \(f(s.maxInflation)) pt\n"
        out +=
            "- space under what the cell draws (cell height - drawn bottom): changed by more than 1.5 pt for \(s.slackItemsThatMoved) of \(s.slackItems) cells (max range \(f(s.maxSlackRange)) pt); drawn top within the cell changed for \(s.inkTopItemsThatMoved) cells (max range \(f(s.maxInkTopRange)) pt)\n"
        out +=
            "- mismatch samples |cell - drawn| > 0.5 on screen: \(s.mismatchOnScreen) of \(s.mismatchSamplesOnScreen) sampled; max \(f(s.mismatchMaxOnScreen)) pt\n"
        out +=
            "- mismatch samples incl. overscan: \(s.mismatchAll) of \(s.mismatchSamples) sampled; max \(f(s.mismatchMaxAll)) pt\n"
        out +=
            "- mismatch samples by cell safe area: with an inset \(s.mismatchWithSafeInset), without \(s.mismatchWithoutSafeInset)\n"
        out += "- mismatch at rest (after the pass settled): \(s.mismatchAtRest); max \(f(s.mismatchMaxAtRest)) pt\n"
        out +=
            "- estimate error over \(s.firstMeasures) first measurements: mean |estimate - measured| \(f(s.estimateMeanAbs)), max \(f(s.estimateMaxAbs)), mean signed \(f(s.estimateMeanSigned))\n"
        out += "- dequeues: \(s.dequeues), of which without a measured height: \(s.dequeuesUnmeasured)\n"
        out += "- invalidations: \(s.invalidations) (compensated \(s.invalidationsCompensated))\n"
        out += "  - by branch: \(counts(s.invalidationsByBranch))\n"
        out += "  - by position: \(counts(s.invalidationsByPosition))\n"
        out += "  - by branch/position: \(counts(s.invalidationsByBranchAndPosition))\n"
        out += "- engine offset writes by site: \(counts(s.offsetWritesBySite))\n\n"
        return out
    }

    static func markdown(passes: [PassData], deviceNote: String) -> String {
        var out = "# Transcript scroll harness report\n\n\(deviceNote)\n\n"
        out += "## Totals\n\n"
        for scenario in scenarios(passes) {
            let own = passes.filter { $0.scenario == scenario }
            out += statsBlock("Scenario \(scenario) (all passes)", own)
            if own.count > 1 {
                for pass in own { out += statsBlock("\(pass.title): \(pass.mode), \(f(pass.stepSize)) pt per step", [pass]) }
            }
        }

        let jumps = passes.flatMap { pass in pass.jumps.map { (pass.title, $0) } }
            .sorted { abs($0.1.amount) > abs($1.1.amount) }
        out += "## Top 20 jumps (cell frames and rows)\n\n"
        if jumps.isEmpty { out += "No jumps.\n\n" }
        for (title, jump) in jumps.prefix(20) {
            out +=
                "- \(title) step \(jump.step) \(jump.kind) \(jump.item): \(String(format: "%+.2f", jump.amount)) pt "
                + "(screenY \(f(jump.screenYPrevious)) -> \(f(jump.screenYNow)), commanded \(f(jump.commandedMotion)), "
                + (jump.onScreen ? "on screen" : "overscan") + ")\n"
            if jump.context.isEmpty { out += "  - no invalidation or engine offset write in this step\n" }
            for line in jump.context { out += "  - \(line)\n" }
        }

        let gaps = passes.flatMap { pass in pass.gaps.map { (pass.title, $0) } }
            .sorted { abs($0.1.drift) > abs($1.1.drift) }
        out += "\n## Top 20 gap drifts (a turn's last content to the next turn's first, between two steps)\n\n"
        if gaps.isEmpty { out += "No gap drift.\n" }
        for (title, gap) in gaps.prefix(20) {
            out +=
                "- \(title) step \(gap.step) [\(gap.kind)] \(gap.upper) -> \(gap.lower): gap \(f(gap.previousGap)) -> \(f(gap.gap)) "
                + "(\(String(format: "%+.2f", gap.drift)) pt)" + (gap.onScreen ? ", on screen" : ", overscan") + "\n"
            for line in passes.first(where: { $0.title == title })?.context(forStep: gap.step) ?? [] {
                out += "  - \(line)\n"
            }
        }
        let ranges = passes.flatMap { pass in pass.gapRanges.values.map { (pass.title, $0) } }
            .sorted { $0.1.range > $1.1.range }
        out += "\n## Top 20 gap ranges (largest min-to-max of one pair's gap over a pass)\n\n"
        for (title, range) in ranges.prefix(20) {
            out +=
                "- \(title) [\(range.kind)] \(range.upper) -> \(range.lower): first \(f(range.first)), min \(f(range.minimum)), max \(f(range.maximum)), range \(f(range.range))\n"
        }

        let mismatches = passes.flatMap { pass in pass.mismatches.map { (pass.title, $0) } }
            .sorted { abs($0.1.mismatch) > abs($1.1.mismatch) }
        out += "\n## Top 20 mismatches\n\n"
        if mismatches.isEmpty { out += "No mismatches.\n\n" }
        for (title, record) in mismatches.prefix(20) {
            out +=
                "- \(title) step \(record.step) \(record.item): cell \(f(record.cellHeight)) vs drawn \(f(record.drawnHeight)) "
                + "= \(String(format: "%+.2f", record.mismatch)) pt"
                + (record.onScreen ? ", on screen" : ", overscan") + (record.atRest ? ", at rest" : "") + "\n"
        }

        let estimates = passes.flatMap { pass in
            pass.invalidations.filter(\.firstMeasure).map { (pass.title, $0) }
        }
        .sorted { abs($0.1.delta) > abs($1.1.delta) }
        out += "\n## Top 10 estimate errors\n\n"
        for (title, record) in estimates.prefix(10) {
            out += "- \(title) step \(record.step) \(record.summary)\n"
        }
        return out + "\n"
    }

    static func json(passes: [PassData], deviceNote: String) throws -> Data {
        var scenarioStats: [String: Any] = [:]
        for scenario in scenarios(passes) {
            scenarioStats[scenario] = HarnessStats(passes.filter { $0.scenario == scenario }).json
        }
        let passJSON: [[String: Any]] = passes.map { pass in
            [
                "scenario": pass.scenario, "name": pass.name, "mode": pass.mode, "stepSize": pass.stepSize,
                "wallSeconds": pass.wallSeconds, "stats": HarnessStats([pass]).json,
                "steps": pass.steps.map(\.json), "invalidations": pass.invalidations.map(\.json),
                "offsetWrites": pass.offsetWrites.map(\.json), "dequeues": pass.dequeues.map(\.json),
                "jumps": pass.jumps.map(\.json), "mismatches": pass.mismatches.map(\.json),
                "gaps": pass.gaps.map(\.json), "gapRanges": pass.gapRanges.values.map(\.json),
                "inflation": pass.inflation,
                "sampleColumns": [
                    "step", "item", "screenY", "cellHeight", "drawnHeight", "safeTop", "safeBottom",
                    "firstRowMinY", "lastRowMaxY", "inkTop", "inkBottom",
                ],
                "samples": pass.samples.map(\.json),
            ]
        }
        let root: [String: Any] = ["device": deviceNote, "scenarios": scenarioStats, "passes": passJSON]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
}
