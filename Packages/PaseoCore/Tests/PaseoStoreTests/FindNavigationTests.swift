import Foundation
import Testing
import PaseoProtocol
@testable import PaseoStore

/// Find in chat, the pure part: stepping wraps, a located message resolves to its row and turn, the
/// transcript window grows to include the target.
@Suite struct FindNavigationTests {
    private func row(_ seq: Int, _ item: TimelineItem, pending: Bool = false) -> TimelineRow {
        TimelineRow(
            id: "seq:\(seq)", turnId: "t", item: item, timestamp: "2026-11-08T21:00:00.000Z",
            seqStart: seq, seqEnd: seq, isPending: pending)
    }
    private func user(_ seq: Int) -> TimelineRow { row(seq, .userMessage(.init(text: "q"))) }
    private func prose(_ seq: Int) -> TimelineRow { row(seq, .assistantMessage(.init(text: "a"))) }
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
        // The search saw the answer end at seq 4 of a turn; it streamed on and now ends at 5.
        let grown: [Turn] = [turn(0, user: user(1), [.prose(prose(5))])]
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

    @Test func aUserMatchNeverResolvesToAnAssistantRowOrAnotherRole() {
        #expect(FindNavigation.target(in: turns, seq: 5, role: .user) == .init(turnIndex: 2, rowSeqEnd: 7))
        #expect(FindNavigation.target(in: turns, seq: 8, role: .user) == nil)
        #expect(FindNavigation.target(in: turns, seq: 3, role: .unknown("x")) == nil)
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
}
