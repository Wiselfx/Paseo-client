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

    /// A message longer than this (characters) is taller than a screen: it rests where its match is
    /// (`occurrenceFraction`) rather than at its middle.
    public static let longMessage = 800

    /// Steps `index` by `delta` through `count` matches, wrapping at both ends (upstream
    /// `navigate`: `(index + locations.length) % locations.length`). Zero when nothing matched.
    public static func wrapped(_ index: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let next = (index + delta) % count
        return next < 0 ? next + count : next
    }

    /// Resolves a located message to a loaded row: the row of the same kind whose range holds `seq`.
    /// The daemon locates a message by the `seqEnd` of its projected row; a message that kept streaming
    /// since has a later `seqEnd` but the same `seqStart`, so the old `seqEnd` is still inside its range
    /// (upstream resolves it by "the first message of that role at or after the seq, before the next
    /// prompt", `chat-find/model.ts` `target`; containment is the exact form of the same idea, and
    /// never lands on a neighbouring message when the located one is not loaded). Nil when the message
    /// is not loaded: the caller fetches its window (`HostSession.loadTimelineWindow`).
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
            if wantsUser {
                if let user = turn.userMessage, !user.isPending, user.seqStart <= seq, seq <= user.seqEnd {
                    return Target(turnIndex: turnIndex, rowSeqEnd: user.seqEnd)
                }
                continue
            }
            for segment in turn.segments {
                if case .prose(let row) = segment, row.seqStart <= seq, seq <= row.seqEnd {
                    return Target(turnIndex: turnIndex, rowSeqEnd: row.seqEnd)
                }
            }
        }
        return nil
    }

    /// The next stop on the way to a turn the lazy stack will not build when asked for it directly (its
    /// estimate of a far id is off by whole turns, and asking again lands in the same wrong place): the
    /// turn `step` places from the nearest turn the stack has built, toward the target. The estimate of
    /// a turn a few places from one that has been measured is good, so each hop lands near its stop and
    /// the target is built within a few hops. Nil when the target is within `step` of a built turn (ask
    /// for it directly) or nothing has been built.
    public static func hopTarget(targetIndex: Int, builtIndices: [Int], step: Int = 4) -> Int? {
        guard step > 0, let nearest = builtIndices.min(by: {
            abs($0 - targetIndex) < abs($1 - targetIndex)
        }) else { return nil }
        let distance = targetIndex - nearest
        guard abs(distance) > step else { return nil }
        return nearest + (distance > 0 ? step : -step)
    }

    /// The first turn index the transcript's window must start at so that the turn at `target` is
    /// mounted with `lead` turns of context above it. The window only ever grows toward older turns
    /// here (a smaller start index is older).
    public static func windowStart(forTurnAt target: Int, currentStart: Int, lead: Int) -> Int {
        guard target < currentStart else { return currentStart }
        return max(target - lead, 0)
    }

    /// The text of the row `target` names: the prompt or the assistant message.
    public static func text(of target: Target, in turns: [Turn]) -> String? {
        guard turns.indices.contains(target.turnIndex) else { return nil }
        let turn = turns[target.turnIndex]
        if let user = turn.userMessage, user.seqEnd == target.rowSeqEnd,
            case .userMessage(let message) = user.item
        {
            return message.text
        }
        for segment in turn.segments {
            if case .prose(let row) = segment, row.seqEnd == target.rowSeqEnd,
                case .assistantMessage(let message) = row.item
            {
                return message.text
            }
        }
        return nil
    }

    /// How far into `text` the first (or, stepping backward, the last) occurrence of `query` starts, from
    /// 0 to 1. The match's place in a tall message decides where the message rests, so the match, not
    /// the message's middle, is what lands in view. The pattern is upstream's (`ranges.web.ts`
    /// `findRenderedMatches`): case-insensitive, the query's words separated by any run of whitespace.
    /// Nil when the text has no occurrence (the search counted source Markdown the message renders away).
    public static func occurrenceFraction(of query: String, in text: String, last: Bool) -> Double? {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty, !text.isEmpty else { return nil }
        let pattern = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "\\s+")
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let whole = NSRange(text.startIndex..., in: text)
        let match = last
            ? regex.matches(in: text, range: whole).last
            : regex.firstMatch(in: text, range: whole)
        guard let match, whole.length > 0 else { return nil }
        return Double(match.range.location) / Double(whole.length)
    }
}

extension Turn {
    /// The timeline position of the turn's first row. A turn without a leading user message (rewinds,
    /// streamed tails, a partial turn at the edge of a loaded window) starts at its first segment row.
    public var firstRowSeq: Int? {
        if let row = userMessage { return row.seqStart }
        for segment in segments {
            switch segment {
            case .work(let group):
                if let row = group.rows.first { return row.seqStart }
            case .prose(let row), .todo(let row), .notice(let row):
                return row.seqStart
            }
        }
        return nil
    }

    /// The timeline position where the turn's last row ends.
    public var lastRowSeq: Int? {
        for segment in segments.reversed() {
            switch segment {
            case .work(let group):
                if let row = group.rows.last { return row.seqEnd }
            case .prose(let row), .todo(let row), .notice(let row):
                return row.seqEnd
            }
        }
        return userMessage?.seqEnd
    }
}

extension FindNavigation {
    /// The index of the first turn that ends at or after `seq`: where a window that starts at `seq` begins.
    /// A turn's id is its first row's id, so it changes when an older page prepends rows to a partial turn;
    /// a position in the timeline does not. Nil when every turn ends before `seq`.
    ///
    /// Turns are in timeline order, so each turn's last row seq is at least the one before it: the test
    /// is false up to some index and true from there on, and a binary search finds that index in O(log n).
    /// The window start is read on every body pass and every scroll frame, so it must not scan the chat.
    public static func firstTurnIndex(endingAtOrAfter seq: Int, in turns: [Turn]) -> Int? {
        var low = 0
        var high = turns.count
        while low < high {
            let middle = low + (high - low) / 2
            if (turns[middle].lastRowSeq ?? Int.min) >= seq {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low < turns.count ? low : nil
    }

    /// The index nearest `target` (within `0..<count`) for which `isBuilt` holds, searched outward from
    /// `target`, so a built turn a few places away is found in a few steps. A tie goes to the lower index,
    /// as `hopTarget` picks it from an ascending list. Nil when none holds, or `target` is out of range.
    public static func nearestIndex(to target: Int, count: Int, where isBuilt: (Int) -> Bool) -> Int? {
        guard (0..<count).contains(target) else { return nil }
        for distance in 0..<count {
            let below = target - distance
            if below >= 0, isBuilt(below) { return below }
            let above = target + distance
            if distance > 0, above < count, isBuilt(above) { return above }
        }
        return nil
    }
}

