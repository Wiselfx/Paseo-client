import Foundation
import PaseoStore

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
