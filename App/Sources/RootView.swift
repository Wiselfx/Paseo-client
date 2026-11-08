import PaseoStore
import SwiftUI
import PaseoUI

/// Navigation: connect → agents → conversation. Features never know about each other;
/// they're wired together only here.
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        switch model.phase {
        case .setup(let status):
            NavigationStack {
                ConnectView(
                    host: $model.host, port: $model.port, password: $model.password, status: status,
                    onConnect: { Task { await model.connect() } })
            }
        case .connected(let session):
            NavigationStack(path: $model.path) {
                AgentsListView(session: session) { agent in model.path.append(agent.id) }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("Disconnect", systemImage: "bolt.horizontal.circle") { model.disconnect() }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                        }
                    }
                    .navigationDestination(for: String.self) { agentId in
                        ConversationScreen(session: session, agentId: agentId)
                    }
            }
        }
    }
}

/// Opens the conversation store for the screen's lifetime.
private struct ConversationScreen: View {
    let session: HostSession
    let agentId: String
    @State private var store: ConversationStore?

    var body: some View {
        Group {
            if let store {
                ConversationView(store: store)
            } else {
                Palette.background.ignoresSafeArea()
            }
        }
        .onAppear { if store == nil { store = session.conversation(for: agentId) } }
        .onDisappear {
            session.closeConversation(agentId)
            store = nil
        }
    }
}
