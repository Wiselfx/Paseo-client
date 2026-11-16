import Foundation

// One host per daemon (upstream model): a direct row and a relay row for the same daemon merge
// into the relay row, which gains the direct URL as an alternate endpoint. Pure logic only; the
// app adapter (App/Sources/SavedHosts.swift) applies it and moves Keychain items.
//
// Upstream: "If the host was already paired through the relay, Paseo adds the direct connection
// to the same host." (public-docs/connectivity.md:127). The profile is keyed by serverId and
// gains connections (packages/app/src/types/host-connection.ts:297-395).

public enum SavedHostMerge {
    /// Which Keychain password survives a merge. The relay row's password is never overwritten.
    public enum PasswordMove: Sendable, Equatable {
        /// Copy the direct row's password to the relay row's account.
        case moveDirectToRelay
        /// Keep the relay row's password (or leave both empty); the direct row's is dropped.
        case keepRelay
    }

    /// The Keychain rule: the direct row's password moves to the relay row's account only when
    /// the relay row has none.
    public static func passwordMove(relayHasPassword: Bool, directHasPassword: Bool) -> PasswordMove {
        if !relayHasPassword && directHasPassword { return .moveDirectToRelay }
        return .keepRelay
    }

    /// The relay row with the direct row folded in. The relay row keeps its identity: `id`,
    /// `serverID`, `daemonPublicKeyB64`, relay endpoint and URL. It gains `directURL`, takes the
    /// later `lastConnectedAt`, and takes the direct row's label only while its own label is still
    /// the default (the daemon id) (upstream host-connection.ts:352 `nextLabel`).
    public static func merge(direct: SavedHost, into relay: SavedHost) -> SavedHost {
        var merged = relay
        merged.directURL = direct.url
        merged.lastConnectedAt = later(relay.lastConnectedAt, direct.lastConnectedAt)
        let directLabel = direct.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let serverID = relay.serverID, relay.label == serverID, !directLabel.isEmpty {
            merged.label = directLabel
        }
        return merged
    }

    private static func later(_ left: Date?, _ right: Date?) -> Date? {
        switch (left, right) {
        case (nil, nil): return nil
        case (let date?, nil), (nil, let date?): return date
        case (let first?, let second?): return max(first, second)
        }
    }
}

extension SavedHostDuplicates {
    /// The merges to apply: one entry per daemon whose saved rows are exactly one relay row and
    /// one direct row. `keep` is the relay row, `absorb` the direct row; apply with
    /// `SavedHostMerge.merge(direct: absorb, into: keep)`.
    ///
    /// Not merged (unchanged behaviour): two direct rows or two relay rows for one daemon, and a
    /// relay row that already names a different direct endpoint (it has room for one only).
    public static func mergePlan(_ hosts: [SavedHost]) -> [(keep: SavedHost, absorb: SavedHost)] {
        groups(hosts).compactMap { (group) -> (keep: SavedHost, absorb: SavedHost)? in
            let relays = group.filter { $0.isRelay }
            let directs = group.filter { !$0.isRelay }
            guard relays.count == 1, directs.count == 1,
                let relay = relays.first, let direct = directs.first
            else { return nil }
            if let existing = relay.directURL, existing != direct.url { return nil }
            return (keep: relay, absorb: direct)
        }
    }
}
