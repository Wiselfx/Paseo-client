import PaseoStore
import PaseoUI
import SwiftUI

/// The composition root: connect, then hand the live session to the ClaudeUI shell.
/// Features never know about each other; they're wired together only here.
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        switch model.phase {
        case .setup(let status):
            ConnectView(
                host: $model.host, port: $model.port, password: $model.password, status: status,
                onConnect: { Task { await model.connect() } })
        case .connected(let session):
            PaseoShellView(session: session, onDisconnect: { model.disconnect() })
        }
    }
}
