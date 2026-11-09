import PaseoStore
import PaseoUI
import SwiftUI

/// The composition root: connect, then hand the live session to the ClaudeUI shell.
/// Features never know about each other; they're wired together only here.
struct RootView: View {
    @Bindable var model: AppModel
    @Bindable var notifications: NotificationCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PaseoSettingsKeys.appearance) private var appearance = ClaudeAppearance.system.rawValue
    @AppStorage(ClaudeTextScale.contentStorageKey) private var contentTextSize = ClaudeTextScale.Content.medium.rawValue
    @AppStorage(ClaudeTextScale.codeStorageKey) private var codeFontSize = ClaudeTextScale.Code.medium.rawValue
    /// First-run welcome: shown before the first successful host connection, and only while
    /// no saved host exists and nothing has been attempted.
    @AppStorage("paseo.welcome.completed") private var welcomeCompleted = false

    private var colorScheme: ColorScheme? {
        (ClaudeAppearance(rawValue: appearance) ?? .system).colorScheme
    }

    @ViewBuilder private func connectForm(status: ConnectView.Status) -> some View {
        ConnectView(
            host: $model.host, port: $model.port, password: $model.password,
            useTLS: $model.useTLS, connectionURI: $model.connectionURI,
            status: status, hosts: model.savedHostsSnapshot,
            onConnect: { Task { await model.connect() } },
            onConnectSaved: { id in Task { await model.connectToSaved(id) } },
            onForgetSaved: { id in model.forgetSavedHost(id) },
            onRenameSaved: { id, label in model.renameSavedHost(id, label: label) })
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
                if !welcomeCompleted, model.savedHostsSnapshot.isEmpty, case .idle = status {
                    WelcomeView { connectForm(status: status) }
                } else {
                    connectForm(status: status)
                }
            case .connected(let session):
                PaseoShellView(
                    session: session, onDisconnect: { model.disconnect() },
                    notificationTarget: $notifications.pendingTarget
                )
                .environment(
                    \.notificationPermissionAction,
                    { @Sendable in
                        Task { @MainActor in _ = await notifications.requestAuthorization() }
                    })
                .onAppear { deliverNotifications(session) }
                .onChange(of: session.attention.pending) { _, _ in
                    deliverNotifications(session)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { deliverNotifications(session) }
                }
            }
        }
        .id(rebuildKey)
        .preferredColorScheme(colorScheme)
        .environment(\.hostSwitch, model.hostContext)
    }

    /// Drains queued attention intents and hands them to the notification coordinator. Runs on
    /// every change, on appear, and when the app returns to the foreground.
    private func deliverNotifications(_ session: HostSession) {
        let intents = session.attention.drain()
        guard !intents.isEmpty else { return }
        // Sound cues (M12): foreground only, and AttentionCenter already dropped the agent
        // the user is looking at.
        if scenePhase == .active {
            SoundCuePlayer.shared.playCues(for: intents)
        }
        Task { await notifications.deliver(intents) }
    }
}
