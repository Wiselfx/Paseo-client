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

    private func performConnect(
        endpoint: DaemonEndpoint, defaultLabel: String, existingSavedID: UUID?
    ) async {
        phase = .setup(.connecting)
        connection?.disconnect()
        let connection = DaemonConnection(
            endpoint: endpoint, clientId: clientId, appVersion: Self.appVersion)
        self.connection = connection
        do {
            try await connection.connect()
            let savedID = savedHosts.markConnected(
                url: endpoint.url, preferredLabel: defaultLabel, id: existingSavedID)
            SavedHosts.savePassword(password, for: savedID)
            currentHostID = savedID
            refreshHostContext()
            // First successful connection completes the first-run welcome.
            defaults.set(true, forKey: Keys.welcomeCompleted)
            let session = HostSession(client: connection)
            phase = .connected(session)
            await session.start()
        } catch let error as ConnectionError {
            phase = .setup(.failed(Self.describe(error)))
        } catch {
            phase = .setup(.failed(error.localizedDescription))
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

    /// "Add host…": close the current session and return to the connect screen.
    func addHost() {
        disconnect()
    }

    /// Switch host: close the current session cleanly, open the other. One host at a time.
    func switchToHost(_ id: UUID) {
        guard id != currentHostID else { return }
        Task { await connectToSaved(id) }
    }

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
        case .closed(let code, let reason): "Connection closed (\(code)) \(reason)"
        case .protocolViolation(let message): "Unexpected reply from the daemon: \(message)"
        case .disconnected: "Disconnected."
        }
    }
}
