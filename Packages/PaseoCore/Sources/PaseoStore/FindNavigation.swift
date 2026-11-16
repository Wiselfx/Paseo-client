import Foundation
import PaseoProtocol

/// The pure part of find in chat: which row a located match is, which turns must be mounted to
/// show it, and how the chevrons step.
///
/// Upstream: `packages/app/src/agent-stream/chat-find/model.ts` (`target`, `navigate`: the daemon
/// locates messages by `seq` and `role`, the client resolves the row, stepping wraps around).
public enum FindNavigation {
    /// The row a match lives in: the turn's index in `turns` and the row's `seqEnd` (the id the
    /// transcript tags it with, `row:<seqEnd>`).
    public struct Target: Equatable, Sendable {
        public var turnIndex: Int
        public var rowSeqEnd: Int

        public init(turnIndex: Int, rowSeqEnd: Int) {
            self.turnIndex = turnIndex
            self.rowSeqEnd = rowSeqEnd
        }
    }

    /// Steps `index` by `delta` through `count` matches, wrapping at both ends (upstream
    /// `navigate`: `(index + locations.length) % locations.length`). Zero when nothing matched.
    public static func wrapped(_ index: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let next = (index + delta) % count
        return next < 0 ? next + count : next
    }

    /// Resolves a located message to a loaded row. The daemon locates a message by the `seqEnd` of
    /// its projected row; a message that kept streaming since has a later `seqEnd`, so the first
    /// row of the same kind that ends at or after `seq` is the match (upstream `target(location,
    /// exact: false)`). A prompt is a hard boundary: an assistant match is never resolved in a
    /// later response. Nil when the message is not loaded (the caller fetches its window).
    public static func target(
        in turns: [Turn], seq: Int, role: AgentTimelineSearchRequest.Role
    ) -> Target? {
        let wantsUser: Bool
        switch role {
        case .user: wantsUser = true
        case .assistant: wantsUser = false
        case .unknown: return nil
        }
        for (turnIndex, turn) in turns.enumerated() {
            if let user = turn.userMessage, !user.isPending, user.seqEnd >= seq {
                return wantsUser ? Target(turnIndex: turnIndex, rowSeqEnd: user.seqEnd) : nil
            }
            guard !wantsUser else { continue }
            for segment in turn.segments {
                if case .prose(let row) = segment, row.seqEnd >= seq {
                    return Target(turnIndex: turnIndex, rowSeqEnd: row.seqEnd)
                }
            }
        }
        return nil
    }

    /// The first turn index the transcript's window must start at so that the turn at `target` is
    /// mounted with `lead` turns of context above it. The window only ever grows toward older turns
    /// here (a smaller start index is older).
    public static func windowStart(forTurnAt target: Int, currentStart: Int, lead: Int) -> Int {
        guard target < currentStart else { return currentStart }
        return max(target - lead, 0)
    }
}
