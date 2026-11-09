import Foundation
import Testing
import PaseoProtocol
@testable import PaseoStore

/// Acceptance tests for T13 part 2 (mascot state machine). Spec: docs/research/06-dsh-ux-spec.md
/// §3.2 (states, tiers, MIN_SHOW_MS) and §3.4 (minimum viable spec).
@Suite struct MascotStateMachineTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    // MARK: Initial state

    /// §3.2 tier 1 — freshly launched mascot is idle.
    @Test func freshMachineIsIdle() {
        let machine = MascotStateMachine(now: t0)
        #expect(machine.state == .idle)
        #expect(machine.tier == 1)
    }

    // MARK: §3.2 tier 2/3 — thinking vs. working

    /// §3.2 tier 2 — a turn that started with no readable activity is "thinking".
    @Test func turnStartedWithoutActivityIsThinking() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnStarted(at: at(0)))
        #expect(machine.state == .thinking)
        #expect(machine.tier == 2)
    }

    /// §3.2 tier 3 — writing/tools with 1 busy session is "typing".
    @Test func writingWithOneBusySessionIsTyping() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnStarted(at: at(0)))
        machine.handle(.activityChanged(.working, at: at(1)))
        #expect(machine.state == .typing)
        #expect(machine.tier == 3)
    }

    /// §3.2 tier 3 — 2 busy sessions is "music".
    @Test func twoBusySessionsAreMusic() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.busySessionsChanged(count: 2, at: at(0)))
        machine.handle(.activityChanged(.working, at: at(1.5))) // after min-show
        #expect(machine.state == .music)
        #expect(machine.tier == 3)
    }

    /// §3.2 tier 3 — ≥ 3 busy sessions is "building".
    @Test func threeBusySessionsAreBuilding() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.busySessionsChanged(count: 3, at: at(0)))
        machine.handle(.activityChanged(.working, at: at(1.5))) // after min-show
        #expect(machine.state == .building)
        #expect(machine.tier == 3)
    }

    /// §3.2 tier 3 — a reasoning session with busy==1 is "thinking", never "typing".
    @Test func reasoningWithBusySessionIsThinking() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnStarted(at: at(0))) // busy becomes 1 (followed session)
        #expect(machine.state == .thinking)
        machine.handle(.busySessionsChanged(count: 3, at: at(1.5)))
        #expect(machine.state == .thinking) // reasoning outranks the busy count
    }

    /// §3.2 tier 3 — the followed running turn counts as one busy session even if
    /// the store never reports a busy count.
    @Test func runningTurnCountsAsOneBusySession() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnStarted(at: at(0)))
        machine.handle(.activityChanged(.working, at: at(1.5)))
        #expect(machine.state == .typing)
    }

    // MARK: §3.2 tier 4 — subagents

    /// §3.2 tier 4 — exactly 1 subagent running is "music".
    @Test func oneSubagentIsMusic() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.subagentsChanged(count: 1, at: at(0)))
        #expect(machine.state == .music)
        #expect(machine.tier == 4)
    }

    /// §3.2 tier 4 — ≥ 2 subagents running is "conducting" (juggling).
    @Test func twoSubagentsAreConducting() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.subagentsChanged(count: 2, at: at(0)))
        #expect(machine.state == .conducting)
        #expect(machine.tier == 4)
        machine.handle(.subagentsChanged(count: 3, at: at(1.5)))
        #expect(machine.state == .conducting)
    }

    /// §3.2 — subagents outrank the working tier.
    @Test func subagentsOutrankWorking() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.busySessionsChanged(count: 1, at: at(0)))
        machine.handle(.activityChanged(.working, at: at(1.5)))
        machine.handle(.subagentsChanged(count: 1, at: at(3)))
        #expect(machine.state == .music)
        #expect(machine.tier == 4)
    }

    /// §3.2 — when the last subagent finishes, the stage drops back to the
    /// working tier (after the 1 s minimum display).
    @Test func subagentFinishedDropsBackToWorking() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnStarted(at: at(0)))
        machine.handle(.activityChanged(.working, at: at(0.1)))
        machine.handle(.subagentsChanged(count: 2, at: at(0.2))) // conducting
        #expect(machine.state == .conducting)
        machine.handle(.subagentsChanged(count: 0, at: at(2))) // after min-show
        #expect(machine.state == .typing)
        #expect(machine.tier == 3)
    }

    // MARK: §3.2 tier 6 — compacting

    /// §3.2 tier 6 — a compaction of the followed session running is "compacting".
    @Test func compactionRunningIsCompacting() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.compactionStarted(at: at(0)))
        #expect(machine.state == .compacting)
        #expect(machine.tier == 6)
    }

    /// §3.2 tier 6 — compacting outranks the working tier.
    @Test func compactingOutranksWorking() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnStarted(at: at(0)))
        machine.handle(.activityChanged(.working, at: at(1.5)))
        machine.handle(.compactionStarted(at: at(3)))
        #expect(machine.state == .compacting)
    }

    /// §3.2 tier 6 vs 7 — notification outranks compacting.
    @Test func notificationOutranksCompacting() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.compactionStarted(at: at(0)))
        machine.handle(.pendingInteractionsChanged(count: 1, at: at(1.5)))
        #expect(machine.state == .notification)
        #expect(machine.tier == 7)
    }

    // MARK: §3.2 tier 7 — notification

    /// §3.2 tier 7 — a pending interaction (permission/question/plan review),
    /// workspace-wide, is "notification".
    @Test func pendingInteractionIsNotification() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.pendingInteractionsChanged(count: 1, at: at(0)))
        #expect(machine.state == .notification)
        #expect(machine.tier == 7)
    }

    /// §3.2 tier 7 — notification outranks everything except the moments.
    @Test func notificationOutranksSubagentsAndCompacting() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.subagentsChanged(count: 2, at: at(0)))
        machine.handle(.pendingInteractionsChanged(count: 1, at: at(1.5)))
        #expect(machine.state == .notification)

        var machine2 = MascotStateMachine(now: t0)
        machine2.handle(.compactionStarted(at: at(0)))
        machine2.handle(.pendingInteractionsChanged(count: 2, at: at(1.5)))
        #expect(machine2.state == .notification)
    }

    /// §3.2 tier 7 — when the interaction resolves, the mascot falls back
    /// (after the 1 s minimum display).
    @Test func notificationResolvedFallsBackAfterMinShow() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnStarted(at: at(0)))
        machine.handle(.activityChanged(.working, at: at(0.1)))
        machine.handle(.pendingInteractionsChanged(count: 1, at: at(0.2)))
        #expect(machine.state == .notification)
        machine.handle(.pendingInteractionsChanged(count: 0, at: at(0.5))) // within min-show
        #expect(machine.state == .notification)
        machine.handle(.pendingInteractionsChanged(count: 0, at: at(2.0))) // after min-show
        #expect(machine.state == .typing)
    }

    // MARK: §3.2 tier 5 — happy

    /// §3.2 tier 5 — a turn ending `completed`/max-tokens is "happy", once.
    @Test func turnCompletedIsHappy() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnStarted(at: at(0)))
        machine.handle(.activityChanged(.working, at: at(0.1)))
        machine.handle(.turnCompleted(at: at(0.2)))
        #expect(machine.state == .happy)
        #expect(machine.tier == 5)
    }

    /// §3.2 tier 5 — a session finishing unread out of view (attention) is "happy".
    @Test func attentionIsHappy() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.attention(at: at(0)))
        #expect(machine.state == .happy)
        #expect(machine.tier == 5)
    }

    /// §3.2 tier 5 — a successful compaction ending is "happy".
    @Test func compactionEndedSuccessfullyIsHappy() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.compactionStarted(at: at(0)))
        machine.handle(.compactionEnded(failed: false, at: at(1.5)))
        #expect(machine.state == .happy)
        #expect(machine.tier == 5)
    }

    /// §3.2 tier 5 — happy outranks working (5 > 3).
    @Test func happyOutranksWorking() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnStarted(at: at(0)))
        machine.handle(.activityChanged(.working, at: at(0.1)))
        machine.handle(.turnCompleted(at: at(0.2)))
        #expect(machine.state == .happy)
        #expect(machine.state != .typing)
    }

    /// §3.2 tier 5 — happy plays once: after its 5.2 s it retires to the
    /// computed state.
    @Test func happyRetiresAfterFivePointTwoSeconds() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnCompleted(at: at(0)))
        #expect(machine.state == .happy)
        machine.tick(now: at(5.0))
        #expect(machine.state == .happy)
        machine.tick(now: at(5.3))
        #expect(machine.state == .idle)
    }

    // MARK: §3.2 tier 8 — error

    /// §3.2 tier 8 — a turn ending with error/blocked is "error", once.
    @Test func turnFailedIsError() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnStarted(at: at(0)))
        machine.handle(.turnFailed(at: at(1.5)))
        #expect(machine.state == .error)
        #expect(machine.tier == 8)
    }

    /// §3.2 tier 8 — a tool result with isError (excluding AbortError) is "error".
    @Test func toolFailedIsError() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.toolFailed(at: at(0)))
        #expect(machine.state == .error)
        #expect(machine.tier == 8)
    }

    /// §3.2 tier 8 — a compaction that failed is "error".
    @Test func compactionFailedIsError() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.compactionStarted(at: at(0)))
        machine.handle(.compactionEnded(failed: true, at: at(1.5)))
        #expect(machine.state == .error)
        #expect(machine.tier == 8)
    }

    /// §3.2 tier 8 — error plays once: after its 4.8 s it retires.
    @Test func errorRetiresAfterFourPointEightSeconds() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnFailed(at: at(0)))
        #expect(machine.state == .error)
        machine.tick(now: at(4.6))
        #expect(machine.state == .error)
        machine.tick(now: at(5.0))
        #expect(machine.state == .idle)
    }

    /// §3.2 tier 8 — a second failure while error is on stage restarts its clock.
    @Test func repeatedFailureRestartsErrorClock() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnFailed(at: at(0)))
        machine.handle(.toolFailed(at: at(4.0)))
        machine.tick(now: at(4.7)) // 0.7 s after the restart — still error
        #expect(machine.state == .error)
        machine.tick(now: at(9.1)) // past the restarted 4.8 s window
        #expect(machine.state != .error)
    }

    /// §3.2 — error (8) outranks attention/happy (5): a failure during the happy
    /// one-shot preempts it.
    @Test func errorOutranksHappy() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnCompleted(at: at(0))) // happy on stage
        machine.handle(.toolFailed(at: at(1.0))) // error arrives
        #expect(machine.state == .error)
    }

    /// §3.2 — moments queue behind a greater one on stage: a happy moment
    /// arriving during error waits and plays once the error retires.
    @Test func happyQueuesBehindError() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnFailed(at: at(0))) // error on stage
        machine.handle(.attention(at: at(1.0))) // happy arrives → queued
        #expect(machine.state == .error)
        machine.tick(now: at(5.0)) // error retires → queued happy plays
        #expect(machine.state == .happy)
        machine.tick(now: at(10.3)) // happy retires too → idle
        #expect(machine.state == .idle)
    }

    /// §3.2 — a queued moment is coalesced, not duplicated.
    @Test func queuedMomentsAreCoalesced() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnFailed(at: at(0)))
        machine.handle(.attention(at: at(1.0)))
        machine.handle(.attention(at: at(2.0)))
        machine.handle(.attention(at: at(3.0)))
        machine.tick(now: at(5.0))
        #expect(machine.state == .happy)
        machine.tick(now: at(10.3))
        #expect(machine.state == .idle) // only one happy played
    }

    /// §3.2 — a queued moment yields to a greater condition that stands by the
    /// time the stage frees: it stays queued while notification stands, plays
    /// once it resolves.
    @Test func queuedMomentYieldsToStandingNotification() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnFailed(at: at(0)))
        machine.handle(.attention(at: at(1.0))) // queued behind error
        machine.handle(.pendingInteractionsChanged(count: 1, at: at(1.5))) // still behind error
        machine.tick(now: at(5.0)) // error retires; notification stands (7 > 5)
        #expect(machine.state == .notification)
        machine.handle(.pendingInteractionsChanged(count: 0, at: at(6.0)))
        // Notification resolved: the queued happy now plays.
        #expect(machine.state == .happy)
    }

    // MARK: §3.2 — the successful-turn path can never produce .error

    /// §3.2 — a whole successful turn (completion + unread attention + a clean
    /// compaction) never produces the error/failure animation at any step.
    /// This encodes the known bug from a previous attempt: a successful turn
    /// must not be able to land on `.error`.
    @Test func successfulTurnNeverProducesErrorState() {
        var machine = MascotStateMachine(now: t0)
        var states: [MascotState] = [machine.state]
        machine.handle(.turnStarted(at: at(0))); states.append(machine.state)
        machine.handle(.activityChanged(.reasoning, at: at(0.1))); states.append(machine.state)
        machine.handle(.activityChanged(.working, at: at(0.2))); states.append(machine.state)
        machine.handle(.busySessionsChanged(count: 1, at: at(0.3))); states.append(machine.state)
        machine.handle(.subagentsChanged(count: 1, at: at(0.4))); states.append(machine.state)
        machine.handle(.subagentsChanged(count: 0, at: at(1.0))); states.append(machine.state)
        machine.handle(.compactionStarted(at: at(1.1))); states.append(machine.state)
        machine.handle(.compactionEnded(failed: false, at: at(1.6))); states.append(machine.state)
        machine.handle(.turnCompleted(at: at(2.0))); states.append(machine.state)
        machine.handle(.busySessionsChanged(count: 0, at: at(2.1))); states.append(machine.state) // the store reports the session idle
        machine.handle(.attention(at: at(2.5))); states.append(machine.state)
        machine.tick(now: at(10))
        states.append(machine.state)
        machine.tick(now: at(30))
        states.append(machine.state)
        #expect(!states.contains(.error), "successful path never reached .error: \(states)")
        #expect(machine.state == .idle, "settles to idle once everything retires: \(states)")
    }

    /// §3.2 — same guarantee through the failure-free subagent-heavy path.
    @Test func successfulMultiSubagentTurnNeverProducesErrorState() {
        var machine = MascotStateMachine(now: t0)
        var states: [MascotState] = []
        for kind in [
            MascotEvent.turnStarted(at: at(0)),
            .activityChanged(.working, at: at(0.1)),
            .subagentsChanged(count: 3, at: at(0.2)),
            .subagentsChanged(count: 2, at: at(1.0)),
            .busySessionsChanged(count: 2, at: at(1.5)),
            .subagentsChanged(count: 1, at: at(2.0)),
            .subagentsChanged(count: 0, at: at(2.5)),
            .busySessionsChanged(count: 1, at: at(3.0)),
            .turnCompleted(at: at(3.5)),
        ] {
            machine.handle(kind)
            states.append(machine.state)
        }
        #expect(!states.contains(.error), "successful path never reached .error: \(states)")
        #expect(states.contains(.happy))
    }

    /// §3.2 — the error moment is only reachable through a failure signal;
    /// no sequence of non-failure events yields it.
    @Test func errorOnlyComesFromFailureSignals() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnStarted(at: at(0)))
        machine.handle(.activityChanged(.working, at: at(0.1)))
        machine.handle(.busySessionsChanged(count: 3, at: at(0.2)))
        machine.handle(.pendingInteractionsChanged(count: 2, at: at(0.3)))
        machine.handle(.pendingInteractionsChanged(count: 0, at: at(0.4)))
        machine.handle(.compactionStarted(at: at(0.5)))
        machine.handle(.compactionEnded(failed: false, at: at(0.6)))
        machine.handle(.turnCompleted(at: at(0.7)))
        machine.handle(.attention(at: at(0.8)))
        machine.tick(now: at(20))
        #expect(machine.state != .error)
    }

    // MARK: §3.2 — minimum display time (MIN_SHOW_MS = 1000)

    /// §3.2 MIN_SHOW_MS — an equal-tier change (1 → 2 busy sessions, typing →
    /// music) holds the 1 s minimum display.
    @Test func equalTierSwitchWithinMinShowHoldsStage() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.busySessionsChanged(count: 1, at: at(0)))
        machine.handle(.activityChanged(.working, at: at(0.2))) // typing took the stage at 0.2
        machine.handle(.busySessionsChanged(count: 2, at: at(0.5))) // 0.3 s in: blocked
        #expect(machine.state == .typing)
        machine.handle(.busySessionsChanged(count: 2, at: at(1.4))) // 1.2 s in: allowed
        #expect(machine.state == .music)
    }

    /// §3.2 MIN_SHOW_MS — working → building (1 → 3 sessions, same tier 3) also
    /// holds the minimum display.
    @Test func workingToBuildingRespectsMinShow() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.busySessionsChanged(count: 1, at: at(0)))
        machine.handle(.activityChanged(.working, at: at(0.2)))
        machine.handle(.busySessionsChanged(count: 3, at: at(0.6)))
        #expect(machine.state == .typing)
        machine.handle(.busySessionsChanged(count: 3, at: at(2.0)))
        #expect(machine.state == .building)
    }

    /// §3.2 MIN_SHOW_MS — a *greater* tier always preempts, even inside min-show.
    @Test func greaterTierPreemptsWithinMinShow() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.busySessionsChanged(count: 1, at: at(0)))
        machine.handle(.activityChanged(.working, at: at(0.1)))
        machine.handle(.pendingInteractionsChanged(count: 1, at: at(0.4))) // 7 > 3
        #expect(machine.state == .notification)
    }

    // MARK: §3.2 tier 1 — idle & sleeping

    /// §3.2 tier 1 — no pointer/key/work for 60 s → sleeping.
    @Test func idleForSixtySecondsFallsAsleep() {
        var machine = MascotStateMachine(now: t0)
        machine.tick(now: at(59))
        #expect(machine.state == .idle)
        machine.tick(now: at(61))
        #expect(machine.state == .sleeping)
        #expect(machine.tier == 1)
    }

    /// §3.2 tier 1 — activity resets the sleep timer; work counts as activity.
    @Test func activityResetsSleepTimer() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.userActivity(at: at(50)))
        machine.tick(now: at(100))
        #expect(machine.state == .idle)
        machine.tick(now: at(110.1))
        #expect(machine.state == .sleeping)
    }

    /// §3.2 tier 1 — on activity a sleeping mascot wakes once (waking), then idles.
    @Test func activityAfterSleepWakesOnce() {
        var machine = MascotStateMachine(now: t0)
        machine.tick(now: at(61))
        #expect(machine.state == .sleeping)
        machine.handle(.userActivity(at: at(70)))
        #expect(machine.state == .waking)
        machine.tick(now: at(71.1))
        #expect(machine.state == .idle)
        // A second tap right away does not replay waking.
        machine.handle(.userActivity(at: at(71.2)))
        #expect(machine.state == .idle)
    }

    /// §3.2 tier 1 — a busy mascot never sleeps, however long it goes quiet.
    @Test func workingMascotDoesNotSleep() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.turnStarted(at: at(0)))
        machine.handle(.activityChanged(.working, at: at(0.1)))
        machine.tick(now: at(120))
        #expect(machine.state == .typing)
    }

    /// §3.2 tier 1 — the sleep timer keeps running while notifications stand but
    /// resolves: resolving one does not instantly doze (activity at resolve time).
    @Test func pendingInteractionActivityResetsTimer() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.pendingInteractionsChanged(count: 1, at: at(100)))
        machine.handle(.pendingInteractionsChanged(count: 0, at: at(100.5)))
        machine.tick(now: at(130)) // 30 s after resolution
        #expect(machine.state == .idle)
    }

    // MARK: §3.2 — notification coalescing (workspace-wide)

    /// §3.2 — the pending-interactions signal is workspace-wide: count > 1 is
    /// still one notification.
    @Test func multiplePendingInteractionsStillOneNotification() {
        var machine = MascotStateMachine(now: t0)
        machine.handle(.pendingInteractionsChanged(count: 3, at: at(0)))
        #expect(machine.state == .notification)
    }

    // MARK: §3.2 — the tool-failure classifier (isError, excluding AbortError)

    /// §3.2 — `MascotToolError.isFailure`: `status == .failed` is isError, but
    /// AbortError (string, object or array form) is excluded.
    @Test func toolFailureClassifierExcludesAbortError() throws {
        func call(_ status: String, error: String? = nil) throws -> ToolCall {
            var json = #"{"callId":"1","name":"Bash","status":"\#(status)","detail":{"type":"plain_text"}"#
            if let error {
                json += #","error":"\#(error)""#
            }
            json += "}"
            return try JSONDecoder().decode(ToolCall.self, from: Data(json.utf8))
        }

        #expect(try MascotToolError.isFailure(call("failed", error: "exit code 2")))
        #expect(try !MascotToolError.isFailure(call("failed", error: "AbortError: The user aborted")))
        #expect(try MascotToolError.isFailure(call("failed", error: "aborted operation")))
        #expect(try !MascotToolError.isFailure(call("completed", error: "AbortError")))
        #expect(try MascotToolError.isFailure(call("failed")), "no error payload still counts as isError")
        #expect(try !MascotToolError.isFailure(call("failed", error: "aborterror timeout")))
    }

    /// §3.2 — AbortError inside nested objects/arrays is excluded, recursively.
    @Test func toolFailureClassifierIsRecursiveAndCaseInsensitive() {
        let nested: JSONValue = .object(["a": .object(["b": .array([.string("ABORTERROR happened")])])])
        #expect(MascotToolError.containsAbortError(nested))
        #expect(MascotToolError.containsAbortError(.object(["error": .null])) == false)
        #expect(MascotToolError.containsAbortError(.object(["type": .string("aborterror")])))
        #expect(MascotToolError.containsAbortError(.array([.number(1), .string("Error Aborterror abort")])))
        #expect(!MascotToolError.containsAbortError(.object(["items": .array([.number(1), .bool(true)])])))
    }
}
