import Testing
import PaseoStore

/// L2 Part A: best-connection selection and the adaptive switch rule. Cases follow upstream's
/// `connection-selection.test.ts` (packages/app/src/utils/connection-selection.test.ts). Synthetic
/// connection ids only.
@Suite struct ConnectionSelectionTests {
    private func candidates(_ ids: String...) -> [ConnectionCandidate] {
        ids.map { ConnectionCandidate(connectionID: $0) }
    }

    // MARK: selectBest (upstream connection-selection.test.ts)

    @Test func picksAvailableLowestLatencyRegardlessOfTransport() {
        let selected = ConnectionSelection.selectBest(
            candidates: candidates("direct:a", "relay:b"),
            probes: [
                "direct:a": .available(latencyMs: 84),
                "relay:b": .available(latencyMs: 34),
            ])
        #expect(selected == "relay:b")
    }

    @Test func picksLowestLatencyAmongMixedTransportCandidates() {
        let selected = ConnectionSelection.selectBest(
            candidates: candidates("direct:a", "direct:c", "relay:b"),
            probes: [
                "direct:a": .available(latencyMs: 84),
                "direct:c": .available(latencyMs: 41),
                "relay:b": .available(latencyMs: 12),
            ])
        #expect(selected == "relay:b")
    }

    @Test func ignoresUnavailableAndPendingProbes() {
        let selected = ConnectionSelection.selectBest(
            candidates: candidates("direct:a", "relay:b", "direct:c"),
            probes: [
                "direct:a": .pending,
                "relay:b": .unavailable,
                "direct:c": .available(latencyMs: 41),
            ])
        #expect(selected == "direct:c")
    }

    @Test func returnsNilWhenNoCandidateIsAvailable() {
        let selected = ConnectionSelection.selectBest(
            candidates: candidates("direct:a", "relay:b"),
            probes: ["direct:a": .pending, "relay:b": .unavailable])
        #expect(selected == nil)
    }

    @Test func returnsNilWhenNoProbesExistEvenWithCandidates() {
        let selected = ConnectionSelection.selectBest(
            candidates: candidates("direct:a", "relay:b"), probes: [:])
        #expect(selected == nil)
    }

    @Test func returnsNilWithoutCandidates() {
        #expect(
            ConnectionSelection.selectBest(
                candidates: [], probes: ["direct:a": .available(latencyMs: 1)]) == nil)
    }

    @Test func allUnavailableIsNil() {
        let selected = ConnectionSelection.selectBest(
            candidates: candidates("direct:a", "direct:b"),
            probes: ["direct:a": .unavailable, "direct:b": .unavailable])
        #expect(selected == nil)
    }

    @Test func tieKeepsTheEarlierCandidate() {
        let selected = ConnectionSelection.selectBest(
            candidates: candidates("direct:a", "relay:b"),
            probes: [
                "direct:a": .available(latencyMs: 20),
                "relay:b": .available(latencyMs: 20),
            ])
        #expect(selected == "direct:a")
    }

    // MARK: decideSwitch (adaptive rule)

    private func decide(
        active: String?,
        probes: [String: ConnectionProbeState],
        sampled: [String],
        rtt: Double?,
        streak: inout AdaptiveSwitchStreak,
        authRejected: Bool = false
    ) -> String? {
        ConnectionSelection.decideSwitch(
            candidates: candidates("relay:active", "direct:fast", "direct:slow"),
            probes: probes,
            sampledConnectionIDs: sampled,
            activeConnectionID: active,
            activeAuthRejected: authRejected,
            activeRttMs: rtt,
            streak: &streak)
    }

    @Test func thresholdAndConsecutiveProbesMatchUpstream() {
        #expect(ConnectionSelection.adaptiveSwitchThresholdMs == 40)
        #expect(ConnectionSelection.adaptiveSwitchConsecutiveProbes == 3)
    }

    @Test func switchesOnlyAfterThreeConsecutiveWinsByThreshold() {
        var streak = AdaptiveSwitchStreak()
        let probes: [String: ConnectionProbeState] = [
            "relay:active": .available(latencyMs: 120),
            "direct:fast": .available(latencyMs: 50),
        ]
        let sampled = ["direct:fast"]
        #expect(decide(active: "relay:active", probes: probes, sampled: sampled, rtt: 120, streak: &streak) == nil)
        #expect(streak.hitCount == 1)
        #expect(decide(active: "relay:active", probes: probes, sampled: sampled, rtt: 120, streak: &streak) == nil)
        #expect(streak.hitCount == 2)
        #expect(
            decide(active: "relay:active", probes: probes, sampled: sampled, rtt: 120, streak: &streak)
                == "direct:fast")
        #expect(streak == AdaptiveSwitchStreak())
    }

    @Test func belowThresholdNeverSwitchesAndResetsStreak() {
        var streak = AdaptiveSwitchStreak()
        let probes: [String: ConnectionProbeState] = ["direct:fast": .available(latencyMs: 90)]
        // Improvement is 100 - 90 = 10, below 40.
        #expect(
            decide(active: "relay:active", probes: probes, sampled: ["direct:fast"], rtt: 100, streak: &streak)
                == nil)
        #expect(streak == AdaptiveSwitchStreak())
    }

    @Test func improvementExactlyAtThresholdCounts() {
        var streak = AdaptiveSwitchStreak()
        let probes: [String: ConnectionProbeState] = ["direct:fast": .available(latencyMs: 60)]
        // Improvement 100 - 60 = 40, which is not below the threshold.
        _ = decide(active: "relay:active", probes: probes, sampled: ["direct:fast"], rtt: 100, streak: &streak)
        #expect(streak.hitCount == 1)
    }

    @Test func streakResetsWhenTheFastestCandidateChanges() {
        var streak = AdaptiveSwitchStreak()
        let first: [String: ConnectionProbeState] = [
            "direct:fast": .available(latencyMs: 50),
            "direct:slow": .available(latencyMs: 80),
        ]
        _ = decide(active: "relay:active", probes: first, sampled: ["direct:fast", "direct:slow"], rtt: 200, streak: &streak)
        _ = decide(active: "relay:active", probes: first, sampled: ["direct:fast", "direct:slow"], rtt: 200, streak: &streak)
        #expect(streak.connectionID == "direct:fast")
        #expect(streak.hitCount == 2)

        let changed: [String: ConnectionProbeState] = [
            "direct:fast": .available(latencyMs: 150),
            "direct:slow": .available(latencyMs: 80),
        ]
        // direct:slow is now the fastest by threshold: the streak restarts at one for it.
        #expect(
            decide(active: "relay:active", probes: changed, sampled: ["direct:fast", "direct:slow"], rtt: 200, streak: &streak)
                == nil)
        #expect(streak.connectionID == "direct:slow")
        #expect(streak.hitCount == 1)
    }

    @Test func activeOnlyCycleLeavesStreakAlone() {
        var streak = AdaptiveSwitchStreak()
        let probes: [String: ConnectionProbeState] = ["direct:fast": .available(latencyMs: 50)]
        _ = decide(active: "relay:active", probes: probes, sampled: ["direct:fast"], rtt: 200, streak: &streak)
        #expect(streak.hitCount == 1)
        #expect(decide(active: "relay:active", probes: probes, sampled: [], rtt: 200, streak: &streak) == nil)
        #expect(streak.hitCount == 1)
    }

    @Test func allSampledFailuresBreakTheStreak() {
        var streak = AdaptiveSwitchStreak()
        let good: [String: ConnectionProbeState] = ["direct:fast": .available(latencyMs: 50)]
        _ = decide(active: "relay:active", probes: good, sampled: ["direct:fast"], rtt: 200, streak: &streak)
        let failed: [String: ConnectionProbeState] = ["direct:fast": .unavailable]
        #expect(decide(active: "relay:active", probes: failed, sampled: ["direct:fast"], rtt: 200, streak: &streak) == nil)
        #expect(streak == AdaptiveSwitchStreak())
    }

    @Test func noActiveRttMakesNoDecisionAndKeepsStreak() {
        var streak = AdaptiveSwitchStreak()
        let probes: [String: ConnectionProbeState] = ["direct:fast": .available(latencyMs: 50)]
        _ = decide(active: "relay:active", probes: probes, sampled: ["direct:fast"], rtt: 200, streak: &streak)
        #expect(decide(active: "relay:active", probes: probes, sampled: ["direct:fast"], rtt: nil, streak: &streak) == nil)
        #expect(streak.hitCount == 1)
    }

    @Test func missingActiveConnectionTakesBestCandidateWithoutStreak() {
        var streak = AdaptiveSwitchStreak()
        let probes: [String: ConnectionProbeState] = [
            "direct:fast": .available(latencyMs: 50),
            "direct:slow": .available(latencyMs: 80),
        ]
        #expect(decide(active: nil, probes: probes, sampled: [], rtt: nil, streak: &streak) == "direct:fast")
        #expect(
            decide(active: "relay:gone", probes: probes, sampled: [], rtt: nil, streak: &streak)
                == "direct:fast")
        #expect(streak == AdaptiveSwitchStreak())
    }

    @Test func unavailableActiveMovesToBestOtherCandidate() {
        var streak = AdaptiveSwitchStreak()
        let probes: [String: ConnectionProbeState] = [
            "relay:active": .unavailable,
            "direct:fast": .available(latencyMs: 50),
        ]
        #expect(decide(active: "relay:active", probes: probes, sampled: [], rtt: nil, streak: &streak) == "direct:fast")
    }

    @Test func authRejectedActiveMovesOnlyToACandidateSelectBestPicks() {
        // Upstream's unavailable branch calls selectBestConnection, which does not exclude an
        // auth-rejected connection: a rejected active with the lowest available latency stays.
        var streak = AdaptiveSwitchStreak()
        let stillBest: [String: ConnectionProbeState] = [
            "relay:active": .available(latencyMs: 10),
            "direct:fast": .available(latencyMs: 50),
        ]
        #expect(
            decide(active: "relay:active", probes: stillBest, sampled: [], rtt: 10, streak: &streak, authRejected: true)
                == nil)
        // With the active probe pending, the best available candidate is picked.
        let pendingActive: [String: ConnectionProbeState] = [
            "relay:active": .pending,
            "direct:fast": .available(latencyMs: 50),
        ]
        #expect(
            decide(active: "relay:active", probes: pendingActive, sampled: [], rtt: nil, streak: &streak, authRejected: true)
                == "direct:fast")
    }
}
