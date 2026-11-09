import PaseoStore
import PaseoUI
import SwiftUI

/// The composition root: connect, then hand the live session to the ClaudeUI shell.
/// Features never know about each other; they're wired together only here.
struct RootView: View {
    @Bindable var model: AppModel
    @AppStorage(PaseoSettingsKeys.appearance) private var appearance = ClaudeAppearance.system.rawValue

    private var colorScheme: ColorScheme? {
        switch ClaudeAppearance(rawValue: appearance) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        Group {
            switch model.phase {
            case .setup(let status):
                ConnectView(
                    host: $model.host, port: $model.port, password: $model.password,
                    useTLS: $model.useTLS, connectionURI: $model.connectionURI,
                    status: status, hosts: model.savedHostsSnapshot,
                    onConnect: { Task { await model.connect() } },
                    onConnectSaved: { id in Task { await model.connectToSaved(id) } },
                    onForgetSaved: { id in model.forgetSavedHost(id) },
                    onRenameSaved: { id, label in model.renameSavedHost(id, label: label) })
            case .connected(let session):
                PaseoShellView(session: session, onDisconnect: { model.disconnect() })
            }
        }
        .preferredColorScheme(colorScheme)
        .environment(\.hostSwitch, model.hostContext)
    }
}
