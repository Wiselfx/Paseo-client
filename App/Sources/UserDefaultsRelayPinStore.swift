import Foundation
import PaseoStore

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
