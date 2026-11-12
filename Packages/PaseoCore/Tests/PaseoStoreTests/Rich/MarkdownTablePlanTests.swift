import Foundation
import Testing

@testable import PaseoStore

// Phase C §9.1: the pure table rules — label columns, cache keys, grow-only merges.
struct MarkdownTablePlanTests {
    @Test("short non-numeric first cells pin")
    func labelColumnPins() {
        #expect(MarkdownTablePlan.isLabelColumn(["Name", "Alice", "Bob"]))
        #expect(MarkdownTablePlan.isLabelColumn(["Status", "ok", "failed"]))
    }

    @Test("numbers and long text do not pin")
    func numericOrLongColumnDoesNotPin() {
        #expect(!MarkdownTablePlan.isLabelColumn(["2024", "1,024", "$3.50"]))
        #expect(!MarkdownTablePlan.isLabelColumn(["Description", "a very long explanation here"]))
        #expect(!MarkdownTablePlan.isLabelColumn([]))
    }

    @Test("a two-thirds majority of labels still pins")
    func majorityPins() {
        #expect(MarkdownTablePlan.isLabelColumn(["ok", "ok", "1,024"]))
        #expect(!MarkdownTablePlan.isLabelColumn(["ok", "1,024", "2,048"]))
    }

    @Test("numeric strips table decorations")
    func numericStripsDecorations() {
        #expect(MarkdownTablePlan.isNumeric("$1,024.50"))
        #expect(MarkdownTablePlan.isNumeric(" 42% "))
        #expect(MarkdownTablePlan.isNumeric("-17"))
        #expect(!MarkdownTablePlan.isNumeric("v2.0"))
        #expect(!MarkdownTablePlan.isNumeric(""))
    }

    @Test("widths only grow on remeasure")
    func widthsGrowOnly() {
        #expect(MarkdownTablePlan.mergedWidths(
            cached: [100, 80], fresh: [90, 120]) == [100, 120])
        #expect(MarkdownTablePlan.mergedWidths(cached: nil, fresh: [90]) == [90])
        #expect(MarkdownTablePlan.mergedWidths(
            cached: [100], fresh: [90, 120]) == [90, 120])
    }

    @Test("overflow needs more than a point past the viewport")
    func overflowTolerance() {
        #expect(MarkdownTablePlan.overflows(totalWidth: 400, viewportWidth: 390))
        #expect(!MarkdownTablePlan.overflows(totalWidth: 390.5, viewportWidth: 390))
        #expect(!MarkdownTablePlan.overflows(totalWidth: 400, viewportWidth: 0))
    }

    @Test("cache keys separate tables and viewports")
    func cacheKeys() {
        let a = MarkdownTablePlan.cacheKey(headerText: "Name|Age", tableIndex: 0, viewportBucket: 10)
        let b = MarkdownTablePlan.cacheKey(headerText: "Name|Age", tableIndex: 1, viewportBucket: 10)
        let c = MarkdownTablePlan.cacheKey(headerText: "Name|Age", tableIndex: 0, viewportBucket: 11)
        #expect(a != b)
        #expect(a != c)
        #expect(MarkdownTablePlan.viewportBucket(for: 390) == 12)
    }
}
