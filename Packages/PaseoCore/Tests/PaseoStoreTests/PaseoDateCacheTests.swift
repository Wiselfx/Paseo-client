import Foundation
import Testing

@testable import PaseoStore

@Suite struct PaseoDateCacheTests {
    @Test func parsesDaemonStampsAndRepeatsAreEqual() {
        let stamp = "2026-11-08T20:56:19.869Z"
        let first = PaseoDate.parse(stamp)
        let second = PaseoDate.parse(stamp)
        #expect(first != nil)
        #expect(first == second)
        #expect(first == PaseoDate.parseUncached(stamp))
    }

    @Test func plainSecondsStampStillParses() {
        let stamp = "2026-11-08T20:56:19Z"
        #expect(PaseoDate.parse(stamp) == PaseoDate.parseUncached(stamp))
        #expect(PaseoDate.parse(stamp) != nil)
    }

    @Test func garbageIsNilEveryTime() {
        #expect(PaseoDate.parse("not a date") == nil)
        #expect(PaseoDate.parse("not a date") == nil)
    }
}
