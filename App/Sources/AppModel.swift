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
    /// Persisted to the Keychain on a successful connect only.
    var password: String
    private(set) var phase: Phase = .setup(.idle)

    private let defaults = UserDefaults.standard
    private var connection: DaemonConnection?
    private let clientId: String

    private enum Keys {
        static let host = "daemon.host"
        static let port = "daemon.port"
        static let clientId = "client.id"
        static let passwordAccount = "daemon-password"
    }

    init() {
        host = defaults.string(forKey: Keys.host) ?? ""
        port = defaults.string(forKey: Keys.port) ?? "6767"
        password = Keychain.read(account: Keys.passwordAccount) ?? ""
        if let id = defaults.string(forKey: Keys.clientId) {
            clientId = id
        } else {
            clientId = "ios-" + UUID().uuidString.lowercased()
            defaults.set(clientId, forKey: Keys.clientId)
        }
        if !host.isEmpty { Task { await connect() } }
    }

    func connect() async {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let portNumber = Int(port),
            let endpoint = DaemonEndpoint(
                host: trimmedHost, port: portNumber, credential: password.isEmpty ? nil : .password(password))
        else {
            phase = .setup(.failed("That host or port doesn't look right."))
            return
        }
        phase = .setup(.connecting)
        connection?.disconnect()
        let connection = DaemonConnection(endpoint: endpoint, clientId: clientId, appVersion: Self.appVersion)
        self.connection = connection
        do {
            try await connection.connect()
            Keychain.save(password, account: Keys.passwordAccount)
            let session = HostSession(client: connection)
            phase = .connected(session)
            await session.start()
        } catch let error as ConnectionError {
            phase = .setup(.failed(Self.describe(error)))
        } catch {
            phase = .setup(.failed(error.localizedDescription))
        }
    }

    func disconnect() {
        connection?.disconnect()
        connection = nil
        phase = .setup(.idle)
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
