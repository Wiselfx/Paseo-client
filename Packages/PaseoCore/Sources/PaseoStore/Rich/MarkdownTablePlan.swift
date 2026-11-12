import Foundation

// MARK: - MarkdownTablePlan (Phase C §9.1)

// NOTE: The transcript's wide tables never measure per body pass. The pure rules live
// here, tested on Linux: the label-column rule (which tables pin their first column),
// the plan-cache key (stable across a streaming table's re-parses), the grow-only
// width merge (columns may grow mid-stream, never shrink), and the overflow test.
// Measurement itself stays in the `Layout` cache (it needs the real fonts); the plan
// cache seeds it across remounts so scrolling back never remeasures.

/// Pure table-layout rules: strings and numbers in, decisions out.
public enum MarkdownTablePlan {
    /// A label column pins: short, non-numeric first cells in at least two thirds
    /// of body rows (a single-row table lets that cell decide). Numbers, currency
    /// and percents never pin — they scan better scrolling with their column.
    public static func isLabelColumn(_ firstColumnCells: [String]) -> Bool {
        guard !firstColumnCells.isEmpty else { return false }
        let qualifying = firstColumnCells.filter { isShortLabel($0) && !isNumeric($0) }
        return Double(qualifying.count) / Double(firstColumnCells.count) >= 0.66
    }

    /// Short enough to read at a glance: 12 visible characters or fewer, non-blank.
    public static func isShortLabel(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 12
    }

    /// Numeric after stripping the decorations numbers wear in tables: currency
    /// symbols, thousands separators, percent signs, surrounding whitespace.
    public static func isNumeric(_ text: String) -> Bool {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        if cleaned.hasSuffix("%") { cleaned.removeLast() }
        if cleaned.hasPrefix("$") || cleaned.hasPrefix("€") || cleaned.hasPrefix("£")
            || cleaned.hasPrefix("¥")
        {
            cleaned.removeFirst()
        }
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned) != nil
    }

    /// The plan-cache key: the header text (written first, stable while rows stream
    /// in), the table's index in its document (two same-header tables stay apart),
    /// and the viewport bucket (rotation re-plans). Never the row text: the key must
    /// survive every keystroke of a streaming table.
    public static func cacheKey(
        headerText: String, tableIndex: Int, viewportBucket: Int
    ) -> String {
        "table|\(tableIndex)|\(viewportBucket)|\(headerText)"
    }

    /// Viewport buckets of 32 pt: a one-point layout jitter never re-plans.
    public static func viewportBucket(for width: Double) -> Int {
        max(0, Int((width / 32).rounded(.down)))
    }

    /// Grow-only merge: a remeasure may widen columns (a streamed row's long cell),
    /// never narrow them, so content never jumps left under the reader. A column
    /// count change (a ragged streamed row) re-plans from the fresh widths.
    public static func mergedWidths(cached: [Double]?, fresh: [Double]) -> [Double] {
        guard let cached, cached.count == fresh.count else { return fresh }
        return zip(cached, fresh).map { max($0, $1) }
    }

    /// Overflow with a one-point tolerance: at or under the viewport, no scroll UI.
    public static func overflows(totalWidth: Double, viewportWidth: Double) -> Bool {
        viewportWidth > 0 && totalWidth > viewportWidth + 1
    }
}
