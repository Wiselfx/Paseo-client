import Foundation
import PaseoProtocol

// Mascot state machine — the states, priority tiers, events and minimum display
// times from docs/research/06-dsh-ux-spec.md §3.2/§3.4, mapped onto *our* store
// signals (turn running/completed/failed, tool call kinds, subagents, compaction,
// permission/attention, idle time).
//
// Pure: input events carry timestamps, `state` is the output. No I/O, no images,
// no randomness — idle "extras" (idle-look/idle-wave/…) from the spec are not
// implemented (they need a random source; §3.4's minimum viable spec does not
// include them), and the reader-press reactions (priority 10) are not mapped
// because Phase 3 covers store signals only, not pointer hit-testing.
//
// How the Paseo stores feed this machine (an example, not part of the API):
//   · Turn row phase → `.turnStarted` when the active turn id appears,
//     `.turnCompleted` when it lands on `completed`/max-tokens, `.turnFailed`
//     on `failed(_)`/blocked.
//   · `.toolCall` rows: any `.running` with detail `.subAgent` counts as one
//     running subagent → `.subagentsChanged`; a `.failed` tool call whose error
//     is not an AbortError → `.toolFailed`. Reasoning rows → `.activityChanged`.
//   · `.compaction` timeline rows (status `start`/`end`) and the daemon's
//     compaction events → `.compactionStarted` / `.compactionEnded(failed:)`.
//   · `HostSession.pendingPermissions` non-empty → `.pendingInteractionsChanged(n)`.
//   · `AgentSnapshot.requiresAttention` (session finished unread out of view) →
//     `.attention`.
//   · Pointer/key/agent-work activity in the app → `.userActivity` +
//     `.busySessionsChanged(count:)` from the visible session set.

/// The animation the mascot is playing. The DeepSeek-facing names map as:
/// `idle`→"Idle", `thinking`→"Thinking", `typing`→"Answering-and-calling-tools",
/// `conducting`→"Conducting-subagents", `notification`→"Waiting-on-you",
/// `error`→"Failed", `happy`→"Finished", `sleeping`→"Asleep" (spec §3.2).
public enum MascotState: Sendable, Equatable {
    /// Nothing running; activity resets the sleep timer.
    case idle
    /// Tier 1, after `sleepAfter` seconds with no pointer/key/work.
    case sleeping
    /// Tier 1, emitted once when the reader wakes a sleeping mascot.
    case waking
    /// Tier 2 — the followed session is reasoning (or has produced no readable activity).
    case thinking
    /// Tier 3 — working with 1 busy session.
    case typing
    /// Tier 3 — working with 2 busy sessions, or tier 4 with exactly 1 subagent.
    case music
    /// Tier 3 — working with ≥ 3 busy sessions.
    case building
    /// Tier 4 — ≥ 2 subagents of the followed session running ("juggling").
    case conducting
    /// Tier 7 — a session in the workspace (or the followed one, or a followed
    /// subagent) is waiting on a pending interaction: approval, question, plan review.
    case notification
    /// Tier 6 — a compaction of the followed session is running ("sweeping").
    case compacting
    /// Tier 5 — turn completed / max-tokens, unread finish out of view, or a
    /// compaction ended. Plays once for `happyDisplay`.
    case happy
    /// Tier 8 — turn ended blocked/error, tool result `isError` (excluding
    /// AbortError), or a compaction failed. Plays once for `errorDisplay`.
    case error
}

/// What the followed session is doing, as far as the mascot can tell.
public enum MascotActivity: Sendable, Equatable {
    /// Reasoning or no readable activity.
    case reasoning
    /// Writing its answer or calling tools.
    case working
}

/// One signal from the stores, stamped with when it happened.
public enum MascotEvent: Sendable, Equatable {
    /// The followed session's turn became active.
    case turnStarted(at: Date)
    /// Turn ended `completed`/max-tokens.
    case turnCompleted(at: Date)
    /// Turn ended with error/blocked.
    case turnFailed(at: Date)
    /// A tool call ended in `isError`, excluding AbortError (see
    /// `MascotToolError.isFailure`).
    case toolFailed(at: Date)
    /// The followed session's activity class changed (reasoning vs. writing/tools).
    case activityChanged(MascotActivity, at: Date)
    /// Busy sessions in the workspace, the followed session included.
    case busySessionsChanged(count: Int, at: Date)
    /// Running subagents of the followed session.
    case subagentsChanged(count: Int, at: Date)
    case compactionStarted(at: Date)
    case compactionEnded(failed: Bool, at: Date)
    /// Pending interactions waiting on the user, workspace-wide
    /// (approvals, questions, plan reviews).
    case pendingInteractionsChanged(count: Int, at: Date)
    /// A session finished unread out of view (`requiresAttention`).
    case attention(at: Date)
    /// Any pointer/key/work activity. Wakes `sleeping`; resets the 60 s timer.
    case userActivity(at: Date)
}

/// Error-outcome classifier for tool calls, shared with the stores.
/// `ToolCall.status == .failed` is our `isError`; AbortError does not count.
public enum MascotToolError {
    public static func isFailure(_ call: ToolCall) -> Bool {
        guard call.status == .failed else { return false }
        return !containsAbortError(call.error)
    }

    static func containsAbortError(_ value: JSONValue?) -> Bool {
        guard let value else { return false }
        switch value {
        case .string(let text):
            return text.lowercased().contains("aborterror")
        case .array(let items):
            return items.contains(where: containsAbortError)
        case .object(let entries):
            return entries.values.contains(where: containsAbortError)
        case .number, .bool, .null:
            return false
        }
    }
}

/// The mascot state machine (spec §3.2 priority table, §3.4 minimum viable spec).
///
/// Priority tiers (higher wins; `REACTION_PRIORITY` = 10 reactions are not
/// implemented): 8 error > 7 notification > 6 compacting > 5 happy > 4 subagents
/// > 3 working > 2 thinking > 1 idle/sleeping/waking.
///
/// Stage rules (spec: `MIN_SHOW_MS` = 1000, moments queue behind a greater one):
///   · A level that just took the stage holds it at least `minimumDisplay`
///     against an equal/lower challenger. A greater one always preempts.
///   · `error` and `happy` are one-shot moments (`errorDisplay`, `happyDisplay`).
///     A moment fired while a greater-tier moment or stage is on stage queues and
///     plays when the stage frees (the queued instance of the same moment kind is
///     coalesced; a queued moment only plays if no greater-tier condition is
///     standing by then). `waking` plays once per sleep → activity transition.
public struct MascotStateMachine: Sendable, Equatable {
    // MARK: Constants

    /// `MIN_SHOW_MS` — a level that just took the stage holds it at least this long
    /// against an equal/lower one.
    public static let minimumDisplay: TimeInterval = 1.0
    /// `error` is a one-shot, played once for 4.8 s.
    public static let errorDisplay: TimeInterval = 4.8
    /// `happy` is a one-shot, played once for 5.2 s.
    public static let happyDisplay: TimeInterval = 5.2
    /// `waking` plays once on activity after `sleeping`; held for `minimumDisplay`.
    public static let wakingDisplay: TimeInterval = Self.minimumDisplay
    /// `sleeping` after this many seconds with no pointer/key/work.
    public static let sleepAfter: TimeInterval = 60

    // MARK: Output

    public private(set) var state: MascotState = .idle
    /// The priority tier the current state sits at (1–8).
    public private(set) var tier: Int = 1

    // MARK: Signal memory (the stores push; the machine keeps the last values)

    private var turnRunning: Bool = false
    private var activity: MascotActivity = .reasoning
    private var busySessions: Int = 0
    private var subagents: Int = 0
    private var compacting: Bool = false
    private var pendingInteractions: Int = 0
    private var lastActivity: Date

    // MARK: Staging memory

    private var tierSince: Date
    /// While a one-shot moment is on stage, the tier can't be overtaken below its
    /// tier until this time.
    private var momentUntil: Date?
    /// One-shot moments blocked by a greater one on stage, coalesced by kind.
    private var queuedMoments: [QueuedMoment] = []
    private var wakingUntil: Date?

    private struct QueuedMoment: Sendable, Equatable {
        enum Kind: Sendable, Equatable { case error, happy }
        var kind: Kind
    }

    public init(now: Date = Date()) {
        lastActivity = now
        tierSince = .distantPast
    }

    // MARK: - Events

    public mutating func handle(_ event: MascotEvent) {
        switch event {
        case .turnStarted(let at):
            turnRunning = true
            // No readable activity yet — spec tier 2 until writing/tools show up.
            activity = .reasoning
            lastActivity = at
            refresh(now: at)
        case .turnCompleted(let at):
            turnRunning = false
            lastActivity = at
            fireMoment(.happy, at: at)
        case .turnFailed(let at):
            turnRunning = false
            lastActivity = at
            fireMoment(.error, at: at)
        case .toolFailed(let at):
            lastActivity = at
            fireMoment(.error, at: at)
        case .activityChanged(let kind, let at):
            activity = kind
            lastActivity = at
            refresh(now: at)
        case .busySessionsChanged(let count, let at):
            busySessions = max(0, count)
            lastActivity = at
            refresh(now: at)
        case .subagentsChanged(let count, let at):
            subagents = max(0, count)
            lastActivity = at
            refresh(now: at)
        case .compactionStarted(let at):
            compacting = true
            lastActivity = at
            refresh(now: at)
        case .compactionEnded(let failed, let at):
            compacting = false
            lastActivity = at
            fireMoment(failed ? .error : .happy, at: at)
        case .pendingInteractionsChanged(let count, let at):
            pendingInteractions = max(0, count)
            lastActivity = at
            refresh(now: at)
        case .attention(let at):
            lastActivity = at
            fireMoment(.happy, at: at)
        case .userActivity(let at):
            lastActivity = at
            if state == .sleeping {
                // `waking` plays once, then refresh resumes the normal computation.
                state = .waking
                tier = 1
                tierSince = at
                wakingUntil = at.addingTimeInterval(Self.wakingDisplay)
                return
            }
            refresh(now: at)
        }
    }

    /// Advance time without an event: expires one-shot moments and the `sleeping`
    /// transition. Call from a timer if the app wants the mascot to doze off
    /// while nothing else happens.
    public mutating func tick(now: Date) {
        refresh(now: now)
    }

    // MARK: - Staging

    private mutating func fireMoment(_ kind: QueuedMoment.Kind, at now: Date) {
        let target: MascotState = kind == .error ? .error : .happy
        let momentTier = kind == .error ? 8 : 5
        let duration = kind == .error ? Self.errorDisplay : Self.happyDisplay
        if tier < momentTier {
            // Greater moment: preempts whatever is on stage (a lesser moment that
            // was playing is simply replaced, not re-queued).
            applyStage(target, tier: momentTier, now: now, moment: duration, minShow: false)
        } else if tier == momentTier, state == target {
            // Already playing this exact moment: restart its clock.
            momentUntil = now.addingTimeInterval(duration)
        } else {
            // Queued behind a greater one on stage; coalesced by kind.
            if !queuedMoments.contains(where: { $0.kind == kind }) {
                queuedMoments.append(QueuedMoment(kind: kind))
            }
        }
        // Re-evaluate: the greater stage this moment was queued behind may have
        // just cleared (e.g. compactionEnded fires happy in the same event).
        refresh(now: now)
    }

    private mutating func refresh(now: Date) {
        // 1. An active one-shot moment holds the stage until it expires.
        if let until = momentUntil {
            if until > now { return }
            momentUntil = nil
        }
        // 2. `waking` plays once, then normal rules resume.
        if let until = wakingUntil {
            if until > now { return }
            wakingUntil = nil
        }
        let desired = desiredState(now: now)
        // 3. A queued moment plays as soon as nothing greater than it stands —
        //    and the stage it would displace has held for at least MIN_SHOW_MS,
        //    unless the moment itself outranks it (a greater moment always
        //    preempts). Coalesced by kind; otherwise the moment stays queued.
        if let queued = queuedMoments.max(by: { momentPriority($0.kind) < momentPriority($1.kind) }),
           momentPriority(queued.kind) >= desired.tier,
           momentPriority(queued.kind) > tier || now.timeIntervalSince(tierSince) >= Self.minimumDisplay {
            queuedMoments.removeAll { $0.kind == queued.kind }
            playMoment(queued.kind, now: now)
            return
        }
        // 4. Normal staging: greater tiers preempt; equal/lower wait out min-show.
        applyStage(desired.state, tier: desired.tier, now: now, moment: nil, minShow: true)
    }

    private func momentPriority(_ kind: QueuedMoment.Kind) -> Int {
        kind == .error ? 8 : 5
    }

    private mutating func playMoment(_ kind: QueuedMoment.Kind, now: Date) {
        let (state, tier, duration): (MascotState, Int, TimeInterval) =
            kind == .error ? (.error, 8, Self.errorDisplay) : (.happy, 5, Self.happyDisplay)
        self.state = state
        self.tier = tier
        self.tierSince = now
        self.momentUntil = now.addingTimeInterval(duration)
    }

    private mutating func applyStage(_ s: MascotState, tier t: Int, now: Date, moment duration: TimeInterval?, minShow: Bool) {
        if s == state {
            // Same state re-evaluated: keep the original tierSince (it never
            // "re-takes" the stage just because desired recomputed the same).
            return
        }
        let allowed = t > tier || !minShow || now.timeIntervalSince(tierSince) >= Self.minimumDisplay
        guard allowed else { return }
        state = s
        tier = t
        tierSince = now
        momentUntil = duration.map { now.addingTimeInterval($0) }
    }

    /// The tier/state implied by the current conditions, ignoring one-shot moments.
    private func desiredState(now: Date) -> (state: MascotState, tier: Int) {
        if pendingInteractions > 0 { return (.notification, 7) }
        if compacting { return (.compacting, 6) }
        if subagents > 0 { return (subagents == 1 ? .music : .conducting, 4) }
        let busy = max(busySessions, turnRunning ? 1 : 0)
        if busy >= 1 {
            guard activity == .working else { return (.thinking, 2) }
            switch busy {
            case 1: return (.typing, 3)
            case 2: return (.music, 3)
            default: return (.building, 3)
            }
        }
        if now.timeIntervalSince(lastActivity) >= Self.sleepAfter {
            return (.sleeping, 1)
        }
        return (.idle, 1)
    }
}
