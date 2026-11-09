import Foundation
import Observation
import PaseoStore
import PaseoUI

/// App-level state: which daemon, how to log in, and the live session once connected.
/// The only place that creates a `DaemonConnection`.
@MainActor @Observable
final class AppModel {
    enum Phase {
        case setup(ConnectView.Status)
        case connected(HostSession)
    }

    var host: String { didSet { defaults.set(host, forKey: Keys.host) } }
    var port: String { didSet { defaults.set(port, forKey: Keys.port) } }
    /// Persisted through the per-host Keychain entry on a successful connect only.
    var password: String
    var useTLS: Bool { didSet { defaults.set(useTLS, forKey: Keys.useTLS) } }
    var connectionURI: String { didSet { defaults.set(connectionURI, forKey: Keys.connectionURI) } }
    private(set) var phase: Phase = .setup(.idle)

    /// Saved daemons (labels, URLs; passwords live per-host in the Keychain).
    let savedHosts = SavedHosts()
    /// Relay pins (UserDefaults) + Keychain secrets (R17). One per app, owned here.
    let pins = RelayHostPins(store: UserDefaultsRelayPinStore())
    let relaySecrets = SavedHostRelaySecrets()
    /// A saved relay host rejected its stored password (S3): RootView asks for the new one
    /// through the same password sheet the pairing flow uses. Set by `performConnect`,
    /// cleared by RootView once it presents the sheet.
    var relayPasswordRequest: RelayPasswordRequest?

    /// One saved host's password rejection. `Identifiable` (fresh id per instance, so the
    /// sheet re-presents) and `Equatable` by identity — tuples are never Equatable, which
    /// is what `.onChange(of:)` needs.
    struct RelayPasswordRequest: Identifiable, Equatable {
        let id = UUID()
        let offer: ConnectionOffer
        let savedID: UUID
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    }
    /// Injected by the composition root so the sidebar footer and Settings → Hosts can switch.
    let hostContext = HostSwitchContext()
    /// Published snapshot for SwiftUI (phase and forms are observed directly).
    private(set) var savedHostsSnapshot: [HostSwitchEntry] = []

    private let defaults = UserDefaults.standard
    private var connection: DaemonConnection?
    private let clientId: String
    /// The saved-host entry this session is connected to (nil in legacy flows until a connect
    /// succeeds).
    private var currentHostID: UUID?

    private enum Keys {
        static let host = "daemon.host"
        static let port = "daemon.port"
        static let useTLS = "daemon.useTLS"
        static let connectionURI = "daemon.connectionURI"
        static let clientId = "client.id"
        static let passwordAccount = "daemon-password"
        /// Set on the first successful connection; gates the first-run welcome screen.
        static let welcomeCompleted = "paseo.welcome.completed"
    }

    init() {
        host = defaults.string(forKey: Keys.host) ?? ""
        port = defaults.string(forKey: Keys.port) ?? "6767"
        useTLS = defaults.bool(forKey: Keys.useTLS)
        connectionURI = defaults.string(forKey: Keys.connectionURI) ?? ""
        password = Keychain.read(account: Keys.passwordAccount) ?? ""
        if let id = defaults.string(forKey: Keys.clientId) {
            clientId = id
        } else {
            clientId = "ios-" + UUID().uuidString.lowercased()
            defaults.set(clientId, forKey: Keys.clientId)
        }
        migrateLegacyHostIfNeeded()
        wireHostContext()
        hostContext.loadAppearances()
        refreshHostContext()
        if let last = savedHosts.mostRecent {
            // Startup: straight to the last host. On failure the connect screen shows with this
            // host preselected and the error inline.
            Task { await connectToSaved(last.id) }
        } else if !host.isEmpty {
            Task { await connect() }
        }
    }

    // MARK: Connecting

    /// Direct form: host/port/TLS, or the Advanced URI when filled.
    func connect() async {
        let result = ConnectionURI.parse(connectionURI)
        let credential = password.isEmpty ? nil : Credential.password(password)
        let endpoint: DaemonEndpoint
        let defaultLabel: String

        switch result {
        case .empty:
            let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedHost.isEmpty,
                let portNumber = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
                (1...65535).contains(portNumber),
                let built = DaemonEndpoint(
                    host: trimmedHost, port: portNumber, useTLS: useTLS, credential: credential)
            else {
                phase = .setup(.failed("That host or port doesn't look right."))
                return
            }
            endpoint = built
            defaultLabel = trimmedHost
        case .invalid(let message):
            phase = .setup(.failed(message))
            return
        case .valid(let parsed):
            endpoint = DaemonEndpoint(url: parsed.url, credential: credential)
            defaultLabel = parsed.displayHost
        }
        await performConnect(endpoint: endpoint, defaultLabel: defaultLabel, existingSavedID: nil)
    }

    /// A tap on a saved host: connect to it, preselecting its details in the form.
    func connectToSaved(_ id: UUID) async {
        guard let saved = savedHosts.host(id) else {
            phase = .setup(.failed("That host is not saved anymore."))
            refreshHostContext()
            return
        }
        if saved.isRelay {
            guard let offer = Self.relayOffer(for: saved) else {
                phase = .setup(.failed("That host's saved relay link is not valid."))
                return
            }
            do {
                let endpoint = try offer.makeEndpoint(secrets: relaySecrets, pins: pins)
                await performConnect(
                    endpoint: endpoint, defaultLabel: saved.label, existingSavedID: id,
                    relayOffer: offer,
                    passwordToSave: relaySecrets.password(serverID: offer.serverID))
            } catch {
                phase = .setup(.failed(Self.describeRelayFailure(error)))
            }
            return
        }
        guard case .valid(let parsed) = ConnectionURI.parse(saved.url) else {
            phase = .setup(.failed("That host's saved address is not valid."))
            return
        }
        host = parsed.host
        port = String(parsed.port)
        useTLS = parsed.isTLS
        connectionURI = ""
        password = SavedHosts.readPassword(id)
        let credential = password.isEmpty ? nil : Credential.password(password)
        let endpoint = DaemonEndpoint(url: parsed.url, credential: credential)
        await performConnect(endpoint: endpoint, defaultLabel: saved.label, existingSavedID: id)
    }

    /// Rebuilds the validated offer a saved relay host was paired with. The public key comes
    /// back as base64 (it is not a secret); a corrupt saved entry is not a link we can use.
    static func relayOffer(for saved: SavedHost) -> ConnectionOffer? {
        guard let serverID = saved.serverID, let keyB64 = saved.daemonPublicKeyB64,
            let endpoint = saved.relayEndpoint, let useTLS = saved.relayUseTLS,
            let key = try? ConnectionOffer.decodePublicKey(keyB64)
        else { return nil }
        return ConnectionOffer(
            serverID: serverID, daemonPublicKeyB64: keyB64, daemonPublicKey: key,
            relayEndpoint: endpoint, relayUseTLS: useTLS)
    }

    /// What a pairing attempt concluded. `.passwordRequired` means the daemon answered the
    /// (encrypted) hello with a password rejection — the only moment the app asks for one.
    enum RelayConnectOutcome {
        case connected
        case passwordRequired
        case failed(String)
    }

    /// Pairs a scanned/pasted link: connects the relay endpoint for `offer`, optionally
    /// with a password the user just typed. On success the host is saved (keyed on daemon
    /// identity), the password kept in the Keychain, and the pin recorded. On a password
    /// rejection nothing is saved and the session is torn down.
    func connectRelay(offer: ConnectionOffer, password: String?) async -> RelayConnectOutcome {
        let endpoint: DaemonEndpoint
        do {
            endpoint = try offer.makeEndpoint(secrets: relaySecrets, pins: pins, password: password)
        } catch {
            return .failed(Self.describeRelayFailure(error))
        }
        let failure = await performConnect(
            endpoint: endpoint, defaultLabel: offer.serverID, existingSavedID: nil,
            relayOffer: offer, passwordToSave: password?.isEmpty == false ? password : offer.password)
        guard let failure else { return .connected }
        if case .rejected(let reason) = failure,
            reason == "password_required" || reason == "incorrect_password"
        {
            connection?.disconnect()
            connection = nil
            phase = .setup(.idle)
            return .passwordRequired
        }
        return .failed(Self.describe(failure))
    }

    /// A bad endpoint build or a bent saved entry; plain words, same as connect failures.
    static func describeRelayFailure(_ error: Error) -> String {
        "That pairing link doesn't look right."
    }

    @discardableResult
    private func performConnect(
        endpoint: DaemonEndpoint, defaultLabel: String, existingSavedID: UUID?,
        relayOffer: ConnectionOffer? = nil, passwordToSave: String? = nil
    ) async -> ConnectionError? {
        phase = .setup(.connecting)
        connection?.disconnect()
        let connection = DaemonConnection(
            endpoint: endpoint, clientId: clientId, appVersion: Self.appVersion)
        self.connection = connection
        do {
            let serverInfo = try await connection.connect()
            let savedID: UUID
            if let relayOffer {
                // S4: a changed daemon key must not inherit the old key's password.
                let change = pins.record(relayOffer)
                if case .daemonKeyChanged = change {
                    relaySecrets.savePassword("", serverID: relayOffer.serverID)
                }
                savedID = try savedHosts.markConnected(
                    offer: relayOffer, preferredLabel: defaultLabel, id: existingSavedID)
                relaySecrets.savePassword(passwordToSave ?? "", serverID: relayOffer.serverID)
            } else {
                savedID = savedHosts.markConnected(
                    url: endpoint.url, preferredLabel: defaultLabel, id: existingSavedID,
                    daemonServerID: serverInfo.serverId)
                SavedHosts.savePassword(password, for: savedID)
            }
            currentHostID = savedID
            refreshHostContext()
            // First successful connection completes the first-run welcome.
            defaults.set(true, forKey: Keys.welcomeCompleted)
            let session = HostSession(client: connection)
            phase = .connected(session)
            await session.start()
            return nil
        } catch let error as ConnectionError {
            // S3: a saved relay host rejecting its stored password reroutes into the
            // password sheet (RootView reads relayPasswordRequest), not a dead-end failure.
            // Saved host only: the pairing path (existingSavedID == nil) gets its own
            // prompt from connectRelay's .passwordRequired, so re-review N5 doesn't double-fire.
            if let relayOffer, let savedID = existingSavedID,
                case .rejected(let reason) = error,
                reason == "password_required" || reason == "incorrect_password"
            {
                relayPasswordRequest = RelayPasswordRequest(offer: relayOffer, savedID: savedID)
                phase = .setup(.idle)
                return error
            }
            phase = .setup(.failed(Self.describe(error)))
            return error
        } catch {
            phase = .setup(.failed(error.localizedDescription))
            return .transport(error.localizedDescription)
        }
    }

    // MARK: Session lifecycle

    func disconnect() {
        connection?.disconnect()
        connection = nil
        currentHostID = nil
        phase = .setup(.idle)
        refreshHostContext()
    }

    /// "Add host…": close the current session and return to the connect screen, with the
    /// add-host methods sheet up (RootView).
    func addHost() {
        disconnect()
        addHostRequested = true
    }

    /// RootView shows the add-host methods sheet while true.
    var addHostRequested = false

    /// Switch host: close the current session cleanly, open the other. One host at a time.
    func switchToHost(_ id: UUID) {
        guard id != currentHostID else { return }
        Task { await connectToSaved(id) }
    }

    /// The saved-host id this session is connected to (nil before the first successful
    /// connect). M20's deep links use it to decide whether a link can route immediately.
    var connectedHostID: UUID? { currentHostID }

    // MARK: Saved hosts

    func forgetSavedHost(_ id: UUID) {
        savedHosts.forget(id)
        SavedHosts.savePassword("", for: id)
        if currentHostID == id { currentHostID = nil }
        refreshHostContext()
    }

    /// Danger zone (M16): forgets the saved endpoint + Keychain secret, then if it was the
    /// connected host, switches to another saved host or back to the connect screen.
    func removeHost(_ id: UUID) {
        let wasCurrent = currentHostID == id
        if let saved = savedHosts.host(id), let serverID = saved.serverID {
            pins.forget(serverID: serverID)
            relaySecrets.savePassword("", serverID: serverID)
        }
        forgetSavedHost(id)
        hostContext.removeAppearance(for: id)
        guard wasCurrent else { return }
        if let other = savedHosts.mostRecent {
            Task { await connectToSaved(other.id) }
        } else {
            disconnect()
        }
    }

    func renameSavedHost(_ id: UUID, label: String) {
        savedHosts.rename(id, label: label)
        refreshHostContext()
    }

    private func wireHostContext() {
        hostContext.switchTo = { [weak self] id in self?.switchToHost(id) }
        hostContext.addHost = { [weak self] in self?.addHost() }
        hostContext.forgetHost = { [weak self] id in self?.removeHost(id) }
        hostContext.renameHost = { [weak self] id, label in self?.renameSavedHost(id, label: label) }
    }

    private func refreshHostContext() {
        let entries = savedHosts.entries(current: currentHostID)
        hostContext.update(hosts: entries)
        savedHostsSnapshot = entries
    }

    /// Pre-M1b versions kept one global host/port/password; adopt them as the first saved host.
    private func migrateLegacyHostIfNeeded() {
        guard savedHosts.hosts.isEmpty, !host.isEmpty else { return }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = "\(useTLS ? "wss" : "ws")://\(trimmedHost):\(trimmedPort)/ws"
        let trimmedPassword = password
        let id = savedHosts.insert(label: trimmedHost, url: url, lastConnectedAt: Date())
        SavedHosts.savePassword(trimmedPassword, for: id)
        Keychain.save("", account: Keys.passwordAccount)
    }

    private static var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    static func describe(_ error: ConnectionError) -> String {
        switch error {
        case .rejected(let reason):
            switch reason {
            case "password_required": "This daemon needs a password."
            case "incorrect_password": "Wrong password."
            case "incompatible_protocol": "This daemon's version isn't compatible. Update Paseo."
            default: "The daemon refused the connection (\(reason))."
            }
        case .timeout: "The daemon didn't answer. Check the address and that it's running."
        case .transport(let message): "Couldn't reach the daemon: \(message)"
        case .closed(let code, let reason):
            switch code {
            case 4002:
                // Terminal (R17): protected handshake failed — relinking the same way will fail again.
                "The pairing link didn't work. Ask the daemon to show a new pairing code."
            case 4003:
                "The encrypted connection failed. Check the pairing link and try again."
            default:
                "Connection closed (\(code)) \(reason)"
            }
        case .protocolViolation(let message): "Unexpected reply from the daemon: \(message)"
        case .disconnected: "Disconnected."
        }
    }
}
