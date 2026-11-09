import Foundation
import PaseoStore
import PaseoUI

/// The saved-hosts store. JSON in UserDefaults (labels and URLs are not secrets; relay hosts
/// persist server id + public key, never key material beyond the public key); passwords go
/// through `Keychain`. App-scoped: `AppModel` owns the only instance.
///
/// Relay hosts key on `serverID` (+ daemon key) via `SavedHost.identityKey` (PaseoKit), so
/// re-pairing finds the same host. Blobs written by the pre-relay client decode with nil
/// relay fields — id, URL and Keychain password survive untouched (migration-tested in
/// `SavedHostIdentityTests`).
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

    func host(matchingURL url: String) -> SavedHost? {
        hosts.first { $0.url == url }
    }

    func host(serverID: String) -> SavedHost? {
        hosts.first { $0.serverID == serverID }
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

    /// A successful connection: upsert by URL (or `id`, when re-connecting a saved host) and
    /// mark it connected now. Returns the saved host's id.
    @discardableResult
    func markConnected(url: URL, preferredLabel: String, id: UUID? = nil) -> UUID {
        let urlString = url.absoluteString
        let now = Date()
        if let id, hosts.contains(where: { $0.id == id }) {
            guard let index = hosts.firstIndex(where: { $0.id == id }) else { return id }
            hosts[index].lastConnectedAt = now
            persist()
            return id
        }
        if let index = hosts.firstIndex(where: { $0.url == urlString }) {
            hosts[index].lastConnectedAt = now
            persist()
            return hosts[index].id
        }
        let saved = SavedHost(id: UUID(), label: preferredLabel, url: urlString, lastConnectedAt: now)
        hosts.append(saved)
        persist()
        return saved.id
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
            return id
        }
        if let index = hosts.firstIndex(where: { $0.identityKey == "relay:\(offer.serverID)" }) {
            fill(&hosts[index])
            persist()
            return hosts[index].id
        }
        var saved = SavedHost(
            id: UUID(), label: preferredLabel, url: relayURLString, lastConnectedAt: now)
        fill(&saved)
        hosts.append(saved)
        persist()
        return saved.id
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
