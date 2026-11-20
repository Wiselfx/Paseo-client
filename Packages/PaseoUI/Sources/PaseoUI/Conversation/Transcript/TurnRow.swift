import PaseoStore
import SwiftUI

// MARK: - TurnRow (R6 §4)

/// One turn in the timeline: a narrow, **equatable** value so a streamed token re-evaluates only
/// the row it changed (`.equatable()` on the `ForEach` row).
///
/// The verbs come from `@Environment(\.chatActions)`-adjacent input — the same `ChatActions`
/// instance for the screen's life, so it is not part of `==`. `ClaudeTurnView` carries the layout
/// and its subviews; this row only decides what the row is told.
struct TurnRow: View, Equatable {
    let turn: Turn
    /// The agent/host capability value rows draw; part of `==` so a capability change re-renders
    /// the row even though its content did not change (E3 §2).
    let availability: TurnActionAvailability
    let isLatest: Bool
    /// The seqEnd of the current find match, non-nil only when it is inside this turn.
    let findSeq: Int?
    /// The seqEnd whose row flashes after a find step, same rule.
    let flashSeq: Int?
    let isLanding: Bool
    let actions: ChatActions
    /// The user stopped this turn; the parent reads `ConversationStore.canceledTurnIds` (N5 A).
    /// Part of `==`: a stopped turn must redraw without its content changing.
    var isCanceled: Bool = false

    @State private var landingStartedAt = Date()

    /// Compared off the main actor, so the conformance does not cross isolation: every compared
    /// input is a plain value (`Turn` is `Sendable`), and `actions` is not part of `==`.
    nonisolated static func == (lhs: TurnRow, rhs: TurnRow) -> Bool {
        lhs.turn == rhs.turn && lhs.availability == rhs.availability
            && lhs.isLatest == rhs.isLatest && lhs.findSeq == rhs.findSeq
            && lhs.flashSeq == rhs.flashSeq && lhs.isLanding == rhs.isLanding
            && lhs.isCanceled == rhs.isCanceled
    }

    var body: some View {
        let _ = PaseoPerf.body("TurnRow")
        let _ = PaseoPerf.why(Self.self)
        ClaudeTurnView(
            turn: turn,
            onMarkdown: actions.markdown,
            highlightedSeq: flashSeq,
            findTarget: findSeq,
            onOpenFile: actions.openFile,
            rewindChoices: availability.rewindChoices,
            onRewind: availability.rewindChoices.isEmpty ? nil : actions.rewind,
            onFork: availability.canForkAtBoundary ? actions.fork : nil,
            onForkInFlight: availability.canForkInFlight ? actions.forkInFlight : nil,
            rewindInFlight: availability.rewindInFlight,
            canForkWorkspace: availability.canForkWorkspace,
            isLatestTurn: isLatest,
            isCanceled: isCanceled
        )
        .overlay(alignment: .top) {
            if isLanding {
                LandingLine(startedAt: landingStartedAt)
                    .offset(y: -8)
            }
        }
        .onChange(of: isLanding) { _, landed in
            if landed { landingStartedAt = Date() }
        }
    }
}

extension Turn {
    /// Does this turn own the row with `seqEnd`? O(rows of this turn), and only ever asked while
    /// find is open.
    func containsRow(seqEnd: Int) -> Bool {
        if let row = userMessage, row.seqEnd == seqEnd { return true }
        for segment in segments {
            switch segment {
            case .work(let group):
                if group.rows.contains(where: { $0.seqEnd == seqEnd }) { return true }
            case .prose(let row), .todo(let row), .notice(let row):
                if row.seqEnd == seqEnd { return true }
            }
        }
        return false
    }
}
