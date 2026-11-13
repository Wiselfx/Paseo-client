import Foundation
import PaseoStore
import PaseoUI

/// The saved-hosts store. JSON in UserDefaults (labels and URLs are not secrets; relay hosts
/// persist server id + public key, never key material beyond the public key); passwords go
/// through `Keychain`. App-scoped: `AppModel` owns the only instance.
///
/// Relay hosts key on `serverID` (+ daemon key) via `SavedHost.identityKey` (PaseoKit), so
/// re-pairing finds the same host. Blobs written by the pre-relay client decode with nil
/// relay fields, and pre-M20b blobs with nil `directServerID` — id, URL and Keychain password
/// survive untouched (migration-tested in `DirectHostServerIDTests`).
@MainActor
final class SavedHosts {
    private(set) var hosts: [SavedHost] = []

    private let defaults = UserDefaults.standard
    private let storageKey = "savedHosts.entries"

    init() {
        load()
    }

    // MARK: Reading

    var mostRecent: SavedHost? {
        hosts.sorted {
            ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast)
        }.first
    }

    func host(_ id: UUID) -> SavedHost? {
        hosts.first { $0.id == id }
    }

    /// A merged relay row also answers to its direct URL: the direct connection belongs to the
    /// same host (`SavedHost.directURL`, upstream connectivity.md:127).
    func host(matchingURL url: String) -> SavedHost? {
        hosts.first { $0.url == url || $0.directURL == url }
    }

    func host(serverID: String) -> SavedHost? {
        hosts.first { $0.daemonServerID == serverID }
    }

    /// Daemon ids that still have more than one saved row. A direct row and a relay row for one
    /// daemon merge as they connect (`mergeDuplicates`); two direct rows or two relay rows for one
    /// daemon stay as they are and render.
    var duplicateDaemonServerIDs: [String] {
        SavedHostDuplicates.serverIDs(hosts)
    }

    /// Most recent first, ready for the picker entries. Relay rows show the relay endpoint
    /// as their line (the WebSocket URL is routing detail).
    func entries(current: UUID?) -> [HostSwitchEntry] {
        hosts
            .sorted {
                ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast)
            }
            .map {
                HostSwitchEntry(
                    id: $0.id, label: $0.label,
                    urlLine: $0.isRelay ? ($0.relayEndpoint ?? $0.url) : $0.url,
                    lastConnectedAt: $0.lastConnectedAt, isCurrent: $0.id == current,
                    isRelay: $0.isRelay)
            }
    }

    /// Every saved host, for the host-confirmation exact-match check (PaseoKit logic).
    var allHosts: [SavedHost] { hosts }

    // MARK: Mutating

    /// A successful direct connection: upsert by URL (or `id`, when re-connecting a saved
    /// host), mark it connected now, and learn the daemon's `serverId` from `server_info`
    /// (M20b) so deep links can find this host before it is the live one. A direct row for a
    /// daemon that is already paired through the relay merges into that relay row. Returns the
    /// id of the row that now stands for the connection: select this one, not the id passed in.
    @discardableResult
    func markConnected(
        url: URL, preferredLabel: String, id: UUID? = nil, daemonServerID: String? = nil
    ) -> UUID {
        let urlString = url.absoluteString
        let now = Date()
        func learn(_ index: Int) {
            hosts[index].learnDirectServerID(daemonServerID)
        }
        if let id, hosts.contains(where: { $0.id == id }) {
            guard let index = hosts.firstIndex(where: { $0.id == id }) else { return id }
            hosts[index].lastConnectedAt = now
            learn(index)
            persist()
            return mergeDuplicates(of: id)
        }
        if let index = hosts.firstIndex(where: { $0.url == urlString || $0.directURL == urlString }) {
            hosts[index].lastConnectedAt = now
            learn(index)
            persist()
            return mergeDuplicates(of: hosts[index].id)
        }
        var saved = SavedHost(
            id: UUID(), label: preferredLabel, url: urlString, lastConnectedAt: now)
        saved.learnDirectServerID(daemonServerID)
        hosts.append(saved)
        persist()
        return mergeDuplicates(of: saved.id)
    }

    /// A successful relay connection: upsert by daemon identity (`identityKey`), never by
    /// URL, so re-pairing reuses the host and its Keychain password. Updates the pinned key,
    /// relay endpoint and label once connected.
    @discardableResult
    func markConnected(offer: ConnectionOffer, preferredLabel: String, id: UUID? = nil) throws -> UUID {
        let now = Date()
        let relayURLString = try offer.relayWebSocketURL().absoluteString
        func fill(_ host: inout SavedHost) {
            host.serverID = offer.serverID
            host.daemonPublicKeyB64 = offer.daemonPublicKeyB64
            host.relayEndpoint = offer.relayEndpoint
            host.relayUseTLS = offer.relayUseTLS
            host.url = relayURLString
            host.lastConnectedAt = now
        }
        if let id, hosts.contains(where: { $0.id == id }) {
            guard let index = hosts.firstIndex(where: { $0.id == id }) else { return id }
            fill(&hosts[index])
            persist()
            return mergeDuplicates(of: id)
        }
        if let index = hosts.firstIndex(where: { $0.identityKey == "relay:\(offer.serverID)" }) {
            fill(&hosts[index])
            persist()
            return mergeDuplicates(of: hosts[index].id)
        }
        var saved = SavedHost(
            id: UUID(), label: preferredLabel, url: relayURLString, lastConnectedAt: now)
        fill(&saved)
        hosts.append(saved)
        persist()
        return mergeDuplicates(of: saved.id)
    }

    /// Upstream keeps one host per daemon id (host-connection.ts `upsertHostConnectionInProfiles`).
    /// Once the row `id` has learned or claimed its daemon id, a direct row and a relay row for
    /// that daemon fold into the relay row (`SavedHostDuplicates.mergePlan`). Returns the id of
    /// the row that now stands for the daemon.
    private func mergeDuplicates(of id: UUID) -> UUID {
        guard let daemonServerID = host(id)?.daemonServerID else { return id }
        var survivor = id
        for step in SavedHostDuplicates.mergePlan(hosts)
        where step.keep.daemonServerID == daemonServerID {
            if step.absorb.id == id { survivor = step.keep.id }
            absorb(direct: step.absorb.id, into: step.keep.id)
        }
        return survivor
    }

    /// Folds the direct row `directID` into the relay row `relayID`. The relay row keeps its
    /// identity (`SavedHostMerge.merge`). The direct password moves to the relay account only
    /// when that account has none, and the direct row's Keychain item is removed with the row.
    private func absorb(direct directID: UUID, into relayID: UUID) {
        guard let direct = host(directID), let relay = host(relayID), let serverID = relay.serverID,
            let relayIndex = hosts.firstIndex(where: { $0.id == relayID })
        else { return }
        let relaySecrets = SavedHostRelaySecrets()
        let directPassword = Self.readPassword(direct.id)
        let relayPassword = relaySecrets.password(serverID: serverID)
        let move = SavedHostMerge.passwordMove(
            relayHasPassword: relayPassword != nil, directHasPassword: !directPassword.isEmpty)
        if move == .moveDirectToRelay {
            relaySecrets.savePassword(directPassword, serverID: serverID)
        }
        // `Keychain.save("")` removes the item.
        Self.savePassword("", for: direct.id)
        hosts[relayIndex] = SavedHostMerge.merge(direct: direct, into: relay)
        hosts.removeAll { $0.id == directID }
        persist()
    }

    /// Adopts an already-known URL into a new entry (legacy migration). Returns the new id.
    @discardableResult
    func insert(label: String, url: String, lastConnectedAt: Date? = nil) -> UUID {
        if let index = hosts.firstIndex(where: { $0.url == url }) { return hosts[index].id }
        let saved = SavedHost(id: UUID(), label: label, url: url, lastConnectedAt: lastConnectedAt)
        hosts.append(saved)
        persist()
        return saved.id
    }

    func rename(_ id: UUID, label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts[index].label = trimmed
        persist()
    }

    func forget(_ id: UUID) {
        hosts.removeAll { $0.id == id }
        persist()
    }

    // MARK: Passwords

    /// One Keychain account per saved host; never logged, never in UserDefaults.
    static func passwordAccount(_ id: UUID) -> String {
        "saved-host.\(id.uuidString.lowercased())"
    }

    static func readPassword(_ id: UUID) -> String {
        Keychain.read(account: passwordAccount(id)) ?? ""
    }

    static func savePassword(_ password: String, for id: UUID) {
        // `Keychain.save("")` removes the item.
        Keychain.save(password, account: passwordAccount(id))
    }

    // MARK: Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        // Tolerant: a corrupt file becomes an empty store rather than a crash. Pre-relay
        // blobs decode because the relay fields are all optional (PaseoKit.SavedHost).
        hosts = (try? JSONDecoder().decode([SavedHost].self, from: data)) ?? []
    }
}

/// Relay pins backed by one UserDefaults JSON array (R17 item 3).
final class UserDefaultsRelayPinStore: RelayPinStore, @unchecked Sendable {
    private let defaults = UserDefaults.standard
    private let key = "relay.pins"

    func pins() -> [RelayPinnedHost] {
        guard let data = defaults.data(forKey: key),
            let pins = try? JSONDecoder().decode([RelayPinnedHost].self, from: data)
        else { return [] }
        return pins
    }

    func pin(serverID: String) -> RelayPinnedHost? {
        pins().first { $0.serverID == serverID }
    }

    func save(_ pin: RelayPinnedHost) {
        var all = pins().filter { $0.serverID != pin.serverID }
        all.append(pin)
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: key)
        }
    }

    func remove(serverID: String) {
        let all = pins().filter { $0.serverID != serverID }
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Relay secrets (S5 review fix): the password lives in the Keychain under its own
/// `relay.<serverID>` account, keyed by daemon identity — genuinely `Sendable`, no
/// indirection through the saved-host list, and existing direct accounts are untouched.
/// (The pre-fix build stored relay passwords under `saved-host.<uuid>`; that branch never
/// merged, so nothing is migrated here — affected dev pairing was simply re-done.)
final class SavedHostRelaySecrets: RelaySecretStore, @unchecked Sendable {
    /// The Keychain account for a relay host: verbatim daemon identity (N9 — base64url ids
    /// are case-sensitive, so the account must be too).
    static func account(_ serverID: String) -> String {
        "relay.\(serverID)"
    }

    func password(serverID: String) -> String? {
        let password = Keychain.read(account: Self.account(serverID)) ?? ""
        return password.isEmpty ? nil : password
    }

    func savePassword(_ password: String, serverID: String) {
        Keychain.save(password, account: Self.account(serverID))
    }
}
