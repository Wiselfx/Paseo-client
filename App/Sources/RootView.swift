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

    /// Fonts and the Pure black palette are read when views are built, so changing them rebuilds
    /// the tree (shell state resets). Light / Dark / System stay live through
    /// `preferredColorScheme` and never rebuild.
    private var rebuildKey: String {
        let pureBlack = ClaudeAppearance(rawValue: appearance) == .pureBlack
        return "\(pureBlack)|\(contentTextSize)|\(codeFontSize)"
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
        .id(rebuildKey)
        .preferredColorScheme(colorScheme)
        .environment(\.hostSwitch, model.hostContext)
    }
}
