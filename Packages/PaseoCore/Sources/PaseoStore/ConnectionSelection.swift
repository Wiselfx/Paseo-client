import Foundation

// Best-connection selection for a host with several connections (a relay route and a direct
// route to the same daemon). Pure: the caller runs the probes and feeds the results in; this
// returns which connection to use. Ported from upstream's connection selection and the
// adaptive switch rule in the host runtime.

/// One connection of a host, as the selection sees it. Upstream `ConnectionCandidate`.
/// Upstream: packages/app/src/utils/connection-selection.ts:3-6
public struct ConnectionCandidate: Sendable, Equatable {
    /// Upstream connection id: `direct:<host:port>` or `relay:<endpoint>` / `relay:wss:<endpoint>`.
    public let connectionID: String

    public init(connectionID: String) {
        self.connectionID = connectionID
    }
}

/// The last probe verdict for one connection. Upstream `ConnectionProbeState`.
/// Upstream: packages/app/src/utils/connection-selection.ts:8-11
public enum ConnectionProbeState: Sendable, Equatable {
    case pending
    case unavailable
    case available(latencyMs: Double)
}

/// The consecutive-win streak for the adaptive switch. Upstream keeps this on the runtime
/// (`switchCandidateConnectionId` / `switchCandidateHitCount`).
/// Upstream: packages/app/src/runtime/host-runtime.ts:1104-1123
public struct AdaptiveSwitchStreak: Sendable, Equatable {
    public private(set) var connectionID: String?
    public private(set) var hitCount: Int

    public init() {
        connectionID = nil
        hitCount = 0
    }

    /// Upstream `resetSwitchCandidate`: host-runtime.ts:1236-1239.
    public mutating func reset() {
        connectionID = nil
        hitCount = 0
    }

    fileprivate mutating func recordWin(for connectionID: String) {
        if self.connectionID == connectionID {
            hitCount += 1
        } else {
            self.connectionID = connectionID
            hitCount = 1
        }
    }
}

public enum ConnectionSelection {
    /// Upstream: packages/app/src/runtime/host-runtime.ts:246
    public static let adaptiveSwitchThresholdMs: Double = 40
    /// Upstream: packages/app/src/runtime/host-runtime.ts:247
    public static let adaptiveSwitchConsecutiveProbes = 3

    /// The available candidate with the lowest latency; a tie keeps the earlier candidate.
    /// Pending and unavailable probes never win. Nil when no candidate is available.
    /// Upstream: packages/app/src/utils/connection-selection.ts:26-50
    public static func selectBest(
        candidates: [ConnectionCandidate],
        probes: [String: ConnectionProbeState]
    ) -> String? {
        fastestAvailable(among: candidates.map(\.connectionID), probes: probes)?.connectionID
    }

    /// The first connection in `connectionIDs` with the lowest available latency. Strictly
    /// lower wins, so a tie keeps the earlier one (upstream `sort(...)[0]` on a stable sort).
    private static func fastestAvailable(
        among connectionIDs: [String],
        probes: [String: ConnectionProbeState]
    ) -> (connectionID: String, latencyMs: Double)? {
        var best: (connectionID: String, latencyMs: Double)?
        for connectionID in connectionIDs {
            guard case .some(.available(let latencyMs)) = probes[connectionID] else { continue }
            if let current = best, !(latencyMs < current.latencyMs) { continue }
            best = (connectionID, latencyMs)
        }
        return best
    }

    /// One probe cycle's switch decision. Returns the connection to switch to, or nil to stay.
    ///
    /// - `candidates`: every connection of the host (upstream `buildConnectionCandidates`).
    /// - `probes`: the probe map after this cycle.
    /// - `sampledConnectionIDs`: the connections probed in this cycle (upstream `connectionsToProbe`).
    /// - `activeConnectionID`: the connection in use, or nil when none is.
    /// - `activeAuthRejected`: the active connection's daemon rejected its credentials.
    /// - `activeRttMs`: heartbeat RTT of the socket in use right now, or nil when there is none.
    /// - `streak`: the consecutive-win streak, updated in place.
    ///
    /// Upstream: packages/app/src/runtime/host-runtime.ts:1021-1123 (`finalizeProbeCycle`).
    public static func decideSwitch(
        candidates: [ConnectionCandidate],
        probes: [String: ConnectionProbeState],
        sampledConnectionIDs: [String],
        activeConnectionID: String?,
        activeAuthRejected: Bool = false,
        activeRttMs: Double?,
        streak: inout AdaptiveSwitchStreak
    ) -> String? {
        // No usable active connection: take the best candidate, no streak involved.
        // Upstream: host-runtime.ts:1035-1047
        guard let active = activeConnectionID,
            candidates.contains(where: { $0.connectionID == active })
        else {
            return selectBest(candidates: candidates, probes: probes)
        }

        // The active connection is unavailable: move to the best other candidate and reset.
        // Upstream: host-runtime.ts:1055-1068
        if probes[active] == .unavailable || activeAuthRejected {
            let next = selectBest(candidates: candidates, probes: probes)
            streak.reset()
            guard let next, next != active else { return nil }
            return next
        }

        // Adaptive switching counts fresh comparisons only. An active-only cycle carries no
        // evidence about any candidate.
        // Upstream: host-runtime.ts:1070-1080
        let sampled = sampledConnectionIDs.filter { $0 != active }
        if sampled.isEmpty { return nil }

        // The fastest available candidate sampled this cycle; the first one wins a tie.
        // Upstream: host-runtime.ts:1081-1094
        // Every sampled candidate failed: that breaks the streak.
        guard let fastest = fastestAvailable(among: sampled, probes: probes) else {
            streak.reset()
            return nil
        }

        // No RTT from the active socket means no comparison this cycle.
        // Upstream: host-runtime.ts:1096-1100
        guard let activeRttMs else { return nil }

        // Upstream: host-runtime.ts:1102-1108
        let improvement = activeRttMs - fastest.latencyMs
        if improvement < adaptiveSwitchThresholdMs {
            streak.reset()
            return nil
        }

        // Upstream: host-runtime.ts:1110-1123
        streak.recordWin(for: fastest.connectionID)
        guard streak.hitCount >= adaptiveSwitchConsecutiveProbes else { return nil }
        streak.reset()
        return fastest.connectionID
    }
}
