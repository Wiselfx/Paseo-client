import Foundation
import Testing
import PaseoProtocol
@testable import PaseoStore

/// The index arithmetic find runs on every scroll frame and every jump tick: the window start is a binary
/// search, and a hop starts from the nearest built turn, found outward. Each is checked against the plain
/// scan it replaces, on inputs with duplicates and ties.
@Suite struct FindNavigationIndexTests {
    private func turn(_ index: Int, lastSeq: Int) -> Turn {
        let row = TimelineRow(
            id: "seq:\(lastSeq)", turnId: "t\(index)", item: .assistantMessage(.init(text: "a")),
            timestamp: "2026-11-08T21:00:00.000Z", seqStart: lastSeq, seqEnd: lastSeq, isPending: false)
        return Turn(
            id: "turn\(index)", turnId: "t\(index)", userMessage: nil, segments: [.prose(row)],
            phase: .completed, startedAt: nil, endedAt: nil)
    }

    /// Turns whose last row seqs are `lastSeqs` (non-decreasing, as the timeline is).
    private func turns(_ lastSeqs: [Int]) -> [Turn] {
        lastSeqs.enumerated().map { turn($0.offset, lastSeq: $0.element) }
    }

    // MARK: Window start

    @Test func binarySearchMatchesTheLinearScanOnTimelineOrder() {
        let shapes: [[Int]] = [
            [],
            [7],
            [3, 3, 5, 8, 8, 8, 13, 21],
            [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
            [10, 10, 10, 10],
            [0, 4, 4, 4, 9, 9, 30],
        ]
        for shape in shapes {
            let all = turns(shape)
            for seq in -1...32 {
                let linear = all.firstIndex { ($0.lastRowSeq ?? Int.min) >= seq }
                #expect(FindNavigation.firstTurnIndex(endingAtOrAfter: seq, in: all) == linear)
            }
        }
    }

    @Test func aWindowStartInTheMiddleOfALongChatFindsTheFirstTurnEndingAtOrAfterIt() {
        let all = turns((0..<5_000).map { $0 * 3 })
        #expect(FindNavigation.firstTurnIndex(endingAtOrAfter: 0, in: all) == 0)
        #expect(FindNavigation.firstTurnIndex(endingAtOrAfter: 1, in: all) == 1)
        #expect(FindNavigation.firstTurnIndex(endingAtOrAfter: 3 * 4_321, in: all) == 4_321)
        #expect(FindNavigation.firstTurnIndex(endingAtOrAfter: 3 * 4_321 + 1, in: all) == 4_322)
        #expect(FindNavigation.firstTurnIndex(endingAtOrAfter: 3 * 4_999 + 1, in: all) == nil)
    }

    // MARK: Nearest built turn

    /// The reference: the first minimal distance in an ascending list, which is what `hopTarget` uses.
    private func referenceNearest(_ target: Int, _ built: [Int]) -> Int? {
        built.min { abs($0 - target) < abs($1 - target) }
    }

    @Test func nearestIndexMatchesTheArgminOverAscendingBuiltIndices() {
        let count = 40
        let builtSets: [[Int]] = [
            [], [0], [39], [5], [30, 31], [2, 8], [10, 20, 30], [0, 39], [12, 13, 14, 15, 16, 17, 18],
        ]
        for built in builtSets {
            let set = Set(built)
            for target in 0..<count {
                let nearest = FindNavigation.nearestIndex(to: target, count: count) { set.contains($0) }
                #expect(nearest == referenceNearest(target, built.sorted()))
            }
        }
    }

    @Test func aTieGoesToTheLowerIndexLikeHopTarget() {
        // 4 and 6 are both two places from 5: the lower one wins, as the ascending list's first minimum does.
        #expect(FindNavigation.nearestIndex(to: 5, count: 10) { [4, 6].contains($0) } == 4)
        #expect(FindNavigation.nearestIndex(to: 5, count: 10) { $0 == 6 } == 6)
    }

    @Test func aHopFromTheNearestIndexIsTheHopFromTheWholeBuiltList() {
        let count = 60
        let builtSets: [[Int]] = [[30, 31], [26, 30], [2, 3], [5], [50, 55], [1, 40]]
        for built in builtSets {
            let set = Set(built)
            for target in 0..<count {
                let nearest = FindNavigation.nearestIndex(to: target, count: count) { set.contains($0) }
                let fromNearest = nearest.flatMap {
                    FindNavigation.hopTarget(targetIndex: target, builtIndices: [$0])
                }
                #expect(fromNearest == FindNavigation.hopTarget(targetIndex: target, builtIndices: built.sorted()))
            }
        }
    }

    @Test func nearestIndexIsNilForAnOutOfRangeTargetOrNothingBuilt() {
        #expect(FindNavigation.nearestIndex(to: -1, count: 5) { _ in true } == nil)
        #expect(FindNavigation.nearestIndex(to: 5, count: 5) { _ in true } == nil)
        #expect(FindNavigation.nearestIndex(to: 2, count: 0) { _ in true } == nil)
        #expect(FindNavigation.nearestIndex(to: 2, count: 5) { _ in false } == nil)
    }
}
