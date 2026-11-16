import Foundation
import Testing
import PaseoProtocol
@testable import PaseoStore

/// Find in chat, the pure part: stepping wraps, a located message resolves to its row and turn, the
/// transcript window grows to include the target.
@Suite struct FindNavigationTests {
    private func row(
        _ seq: Int, _ item: TimelineItem, pending: Bool = false, startsAt: Int? = nil
    ) -> TimelineRow {
        TimelineRow(
            id: "seq:\(startsAt ?? seq)", turnId: "t", item: item, timestamp: "2026-11-08T21:00:00.000Z",
            seqStart: startsAt ?? seq, seqEnd: seq, isPending: pending)
    }
    private func user(_ seq: Int) -> TimelineRow { row(seq, .userMessage(.init(text: "q"))) }
    private func prose(_ seq: Int, startsAt: Int? = nil) -> TimelineRow {
        row(seq, .assistantMessage(.init(text: "a")), startsAt: startsAt)
    }
    private func thought(_ seq: Int) -> TimelineRow { row(seq, .reasoning(.init(text: "r"))) }

    private func turn(_ id: Int, user: TimelineRow?, _ segments: [Turn.Segment]) -> Turn {
        Turn(
            id: "turn\(id)", turnId: "t\(id)", userMessage: user, segments: segments,
            phase: .completed, startedAt: nil, endedAt: nil)
    }

    /// seq 1 user, 2 thought, 3 prose | 4 user, 5 prose, 6 prose | 7 user (no answer yet)
    private var turns: [Turn] {
        [
            turn(0, user: user(1), [.work(.init(rows: [thought(2)])), .prose(prose(3))]),
            turn(1, user: user(4), [.prose(prose(5)), .prose(prose(6))]),
            turn(2, user: user(7), []),
        ]
    }

    // MARK: Stepping

    @Test func steppingWrapsAtBothEnds() {
        #expect(FindNavigation.wrapped(0, delta: 1, count: 3) == 1)
        #expect(FindNavigation.wrapped(2, delta: 1, count: 3) == 0)
        #expect(FindNavigation.wrapped(0, delta: -1, count: 3) == 2)
        #expect(FindNavigation.wrapped(1, delta: -1, count: 3) == 0)
        #expect(FindNavigation.wrapped(0, delta: 1, count: 1) == 0)
        #expect(FindNavigation.wrapped(0, delta: -1, count: 1) == 0)
        #expect(FindNavigation.wrapped(0, delta: 1, count: 0) == 0)
    }

    // MARK: Row resolution

    @Test func aUserMatchResolvesToThePromptRow() {
        let target = FindNavigation.target(in: turns, seq: 4, role: .user)
        #expect(target == .init(turnIndex: 1, rowSeqEnd: 4))
    }

    @Test func anAssistantMatchResolvesToTheProseRowInItsTurn() {
        #expect(FindNavigation.target(in: turns, seq: 3, role: .assistant) == .init(turnIndex: 0, rowSeqEnd: 3))
        #expect(FindNavigation.target(in: turns, seq: 6, role: .assistant) == .init(turnIndex: 1, rowSeqEnd: 6))
    }

    @Test func aMessageThatGrewSinceTheSearchResolvesToItsLaterRow() {
        // The search saw the answer end at seq 4; it streamed on from 2 to 5 and now ends there.
        let grown: [Turn] = [turn(0, user: user(1), [.prose(prose(5, startsAt: 2))])]
        #expect(FindNavigation.target(in: grown, seq: 4, role: .assistant) == .init(turnIndex: 0, rowSeqEnd: 5))
    }

    @Test func anAssistantMatchNeverResolvesInALaterResponse() {
        // Prose 3 is not loaded (the turn holds only its prompt); seq 3 must not land on turn 1's answer.
        let partial: [Turn] = [
            turn(0, user: user(1), []),
            turn(1, user: user(4), [.prose(prose(5))]),
        ]
        #expect(FindNavigation.target(in: partial, seq: 3, role: .assistant) == nil)
    }

    @Test func aUserMatchNeverResolvesToANeighbourOrAnotherRole() {
        // seq 5 is an assistant row; the next prompt (7) is not the match.
        #expect(FindNavigation.target(in: turns, seq: 5, role: .user) == nil)
        #expect(FindNavigation.target(in: turns, seq: 2, role: .user) == nil)
        #expect(FindNavigation.target(in: turns, seq: 7, role: .user) == .init(turnIndex: 2, rowSeqEnd: 7))
        #expect(FindNavigation.target(in: turns, seq: 3, role: .unknown("x")) == nil)
    }

    @Test func anUnloadedOlderMessageDoesNotLandOnTheOldestLoadedOne() {
        // Only turns from seq 100 are loaded; a match at seq 8 (user or assistant) is not among them.
        let loaded: [Turn] = [turn(0, user: user(100), [.prose(prose(101))])]
        #expect(FindNavigation.target(in: loaded, seq: 8, role: .user) == nil)
        #expect(FindNavigation.target(in: loaded, seq: 8, role: .assistant) == nil)
        let headless: [Turn] = [turn(0, user: nil, [.prose(prose(101))])]
        #expect(FindNavigation.target(in: headless, seq: 8, role: .assistant) == nil)
    }

    @Test func anUnloadedMessageResolvesToNothing() {
        #expect(FindNavigation.target(in: turns, seq: 90, role: .assistant) == nil)
        #expect(FindNavigation.target(in: [], seq: 1, role: .user) == nil)
    }

    @Test func aPendingUserMessageIsNotAMatch() {
        let pending = [turn(0, user: row(9, .userMessage(.init(text: "q")), pending: true), [])]
        #expect(FindNavigation.target(in: pending, seq: 9, role: .user) == nil)
    }

    @Test func aTurnWithoutAPromptStillHoldsItsAnswer() {
        let rewound = [turn(0, user: nil, [.prose(prose(12))])]
        #expect(FindNavigation.target(in: rewound, seq: 12, role: .assistant) == .init(turnIndex: 0, rowSeqEnd: 12))
    }

    // MARK: Window

    @Test func theWindowGrowsToTheTargetWithLeadAndNeverShrinks() {
        // Currently mounted from turn 40; a match in turn 20 mounts from 12.
        #expect(FindNavigation.windowStart(forTurnAt: 20, currentStart: 40, lead: 8) == 12)
        // Already mounted: unchanged.
        #expect(FindNavigation.windowStart(forTurnAt: 45, currentStart: 40, lead: 8) == 40)
        // Near the start of the conversation.
        #expect(FindNavigation.windowStart(forTurnAt: 3, currentStart: 40, lead: 8) == 0)
    }

    // MARK: Where the match sits in the message

    @Test func theFirstAndLastOccurrenceAreLocatedByTheirPlaceInTheText() throws {
        let text = "Alpha beta. " + String(repeating: "x", count: 76) + " beta again. " + String(repeating: "y", count: 10)
        let first = try #require(FindNavigation.occurrenceFraction(of: "beta", in: text, last: false))
        let last = try #require(FindNavigation.occurrenceFraction(of: "BETA", in: text, last: true))
        #expect(first < 0.1)
        #expect(last > 0.7 && last < 0.9)
        #expect(FindNavigation.occurrenceFraction(of: "gamma", in: text, last: false) == nil)
        #expect(FindNavigation.occurrenceFraction(of: "  ", in: text, last: false) == nil)
    }

    @Test func aMultiWordQueryMatchesAcrossAnyWhitespace() throws {
        let text = "one two\n\nthree   four five"
        #expect(try #require(FindNavigation.occurrenceFraction(of: "two  three", in: text, last: false)) > 0.1)
        #expect(FindNavigation.occurrenceFraction(of: "a.b", in: "axb", last: false) == nil)
    }

    @Test func theRowTextIsTheMessageOfTheTarget() {
        let sample = [
            turn(0, user: user(1), [.prose(prose(3))]),
        ]
        #expect(FindNavigation.text(of: .init(turnIndex: 0, rowSeqEnd: 1), in: sample) == "q")
        #expect(FindNavigation.text(of: .init(turnIndex: 0, rowSeqEnd: 3), in: sample) == "a")
        #expect(FindNavigation.text(of: .init(turnIndex: 5, rowSeqEnd: 3), in: sample) == nil)
    }

    // MARK: Turn positions

    @Test func aTurnKnowsWhereItStartsAndEnds() {
        let t = turn(0, user: user(1), [.work(.init(rows: [thought(2)])), .prose(prose(3))])
        #expect(t.firstRowSeq == 1)
        #expect(t.lastRowSeq == 3)
        let headless = turn(1, user: nil, [.work(.init(rows: [thought(7), thought(8)]))])
        #expect(headless.firstRowSeq == 7)
        #expect(headless.lastRowSeq == 8)
        let promptOnly = turn(2, user: user(9), [])
        #expect(promptOnly.firstRowSeq == 9)
        #expect(promptOnly.lastRowSeq == 9)
    }

    @Test func aWindowStartSurvivesAnOlderPagePrependingToItsTurn() {
        // The window starts at the turn that begins at seq 40. An older page then prepends rows 30...39 to it:
        // its id (the first row's) would change, its place in the timeline holds.
        let before = [turn(0, user: user(10), [.prose(prose(20))]), turn(1, user: nil, [.prose(prose(45, startsAt: 40))])]
        let after = [turn(0, user: user(10), [.prose(prose(20))]), turn(1, user: nil, [.prose(prose(35, startsAt: 30)), .prose(prose(45, startsAt: 40))])]
        #expect(FindNavigation.firstTurnIndex(endingAtOrAfter: 40, in: before) == 1)
        #expect(FindNavigation.firstTurnIndex(endingAtOrAfter: 40, in: after) == 1)
        #expect(FindNavigation.firstTurnIndex(endingAtOrAfter: 46, in: after) == nil)
        #expect(FindNavigation.firstTurnIndex(endingAtOrAfter: 0, in: after) == 0)
    }

    // MARK: Hops

    @Test func aFarTargetIsReachedInHopsFromTheNearestBuiltTurn() {
        // Built turns 30 and 31; the target is 5: hop to 26 (4 from 30), then from 26 to 22, and so on.
        #expect(FindNavigation.hopTarget(targetIndex: 5, builtIndices: [30, 31]) == 26)
        #expect(FindNavigation.hopTarget(targetIndex: 5, builtIndices: [26, 30]) == 22)
        // Toward a later turn.
        #expect(FindNavigation.hopTarget(targetIndex: 40, builtIndices: [2, 3]) == 7)
        // Close enough to ask for it directly, or nothing built.
        #expect(FindNavigation.hopTarget(targetIndex: 8, builtIndices: [5]) == nil)
        #expect(FindNavigation.hopTarget(targetIndex: 9, builtIndices: [5]) == nil)
        #expect(FindNavigation.hopTarget(targetIndex: 9, builtIndices: []) == nil)
    }
}

