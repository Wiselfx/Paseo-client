import PaseoStore
import PaseoUI
import SwiftUI

/// The composition root: connect, then hand the live session to the ClaudeUI shell.
/// Features never know about each other; they're wired together only here.
struct RootView: View {
    @Bindable var model: AppModel
    @AppStorage(PaseoSettingsKeys.appearance) private var appearance = ClaudeAppearance.system.rawValue
    @AppStorage(ClaudeTextScale.contentStorageKey) private var contentTextSize = ClaudeTextScale.Content.medium.rawValue
    @AppStorage(ClaudeTextScale.codeStorageKey) private var codeFontSize = ClaudeTextScale.Code.medium.rawValue

    private var colorScheme: ColorScheme? {
        (ClaudeAppearance(rawValue: appearance) ?? .system).colorScheme
    }

    var body: some View {
        // Rebuilding on these keys applies theme and font-size changes live.
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
        .id("\(appearance)|\(contentTextSize)|\(codeFontSize)")
        .preferredColorScheme(colorScheme)
        .environment(\.hostSwitch, model.hostContext)
    }
}
