import Foundation
import PaseoUI

/// One daemon this device remembers. Non-secret only — the password lives in the Keychain,
/// one account per host id. The URL never carries credentials.
struct SavedHost: Codable, Identifiable, Equatable {
    var id: UUID
    /// User-editable label; defaults to the host part of the URL.
    var label: String
    /// Full `ws(s)://host:port/ws`, normalized, credential-free.
    var url: String
    var lastConnectedAt: Date?
}

/// The saved-hosts store. JSON in UserDefaults (labels and URLs are not secrets); passwords go
/// through `Keychain`. App-scoped: `AppModel` owns the only instance.
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

    /// Most recent first, ready for the picker entries.
    func entries(current: UUID?) -> [HostSwitchEntry] {
        hosts
            .sorted {
                ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast)
            }
            .map {
                HostSwitchEntry(
                    id: $0.id, label: $0.label, urlLine: $0.url,
                    lastConnectedAt: $0.lastConnectedAt, isCurrent: $0.id == current)
            }
    }

    // MARK: Mutating

    /// A successful connection: upsert by URL (or `id`, when re-connecting a saved host) and mark
    /// it connected now. Returns the saved host's id.
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
        // Tolerant: a corrupt file becomes an empty store rather than a crash.
        hosts = (try? JSONDecoder().decode([SavedHost].self, from: data)) ?? []
    }
}
