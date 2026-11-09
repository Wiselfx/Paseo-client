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
    // Pairing flow (R18): one sheet, driven by this enum, so step transitions swap the
    // content instead of racing dismiss-against-present (dismissals clear the item).
    @State private var pairingSheet: PairingSheet?
    /// The in-flight pairing attempt (S1): Connect is disabled and its completion is the
    /// only one that may touch sheet state.
    @State private var pairingAttempt: UUID?

    /// One pairing question or prompt. `id` is fresh per instance: a new attempt must
    /// re-present the password sheet (S2), not reuse the identity of the old one.
    struct PendingPairing: Identifiable {
        let id = UUID()
        let offer: ConnectionOffer
        let kind: HostConfirmationKind
    }

    enum PairingSheet: Identifiable {
        case methods
        case scan
        case paste(error: String?)
        case confirm(PendingPairing)
        case password(PendingPairing, error: String?)

        var id: String {
            switch self {
            case .methods: "methods"
            case .scan: "scan"
            case .paste(let error): "paste.\(error ?? "")"
            case .confirm(let pending): "confirm.\(pending.id)"
            case .password(let pending, let error): "password.\(pending.id).\(error ?? "")"
            }
        }
    }

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
                    WelcomeView(
                        onScan: { pairingSheet = .scan },
                        onPaste: { pairingSheet = .paste(error: nil) }
                    ) { connectForm(status: status) }
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
        .sheet(isPresented: $model.addHostRequested) {
            AddHostMethodsSheet(
                onDirect: { model.addHostRequested = false },
                onScan: { model.addHostRequested = false; pairingSheet = .scan },
                onPaste: { model.addHostRequested = false; pairingSheet = .paste(error: nil) })
        }
        .sheet(item: $pairingSheet) { sheet in
            switch sheet {
            case .methods:
                AddHostMethodsSheet(
                    onDirect: { pairingSheet = nil },
                    onScan: { pairingSheet = .scan },
                    onPaste: { pairingSheet = .paste(error: nil) })
            case .scan:
                PairScanSheet(
                    onScanned: { payload in
                        stagePairing(payload)
                    },
                    onUsePaste: { pairingSheet = .paste(error: nil) })
            case .paste(let error):
                PastePairingSheet(error: error) { payload in
                    stagePairing(payload)
                }
            case .confirm(let pending):
                HostConfirmationPairingSheet(
                    offer: pending.offer, kind: pending.kind,
                    isAttempting: pairingAttempt != nil) {
                        attemptPairing(pending, password: nil, fromPassword: false)
                    }
            case .password(let pending, let error):
                PairingPasswordSheet(
                    host: displayName(for: pending.offer),
                    error: error,
                    isAttempting: pairingAttempt != nil) { entered in
                        attemptPairing(pending, password: entered, fromPassword: true)
                    }
            }
        }
        .onChange(of: model.relayPasswordRequest) { _, request in
            guard let request else { return }
            // S3: a saved relay host rejected the stored password; ask again here.
            pairingSheet = .password(
                PendingPairing(offer: request.offer, kind: .newHost), error: nil)
        }
    }

    /// The daemon's shown name for the password title (`Password for {{host}}`, en.ts:1837).
    private func displayName(for offer: ConnectionOffer) -> String {
        model.savedHosts.allHosts.first { $0.serverID == offer.serverID }?.label ?? offer.serverID
    }

    /// A scanned/pasted payload: parse it (never log it), then confirm unless the link
    /// matches a saved host exactly (upstream: resolve true without asking).
    private func stagePairing(_ payload: String) {
        do {
            let offer = try ConnectionOffer(link: payload)
            if let kind = HostConfirmation.confirmationKind(
                offer: offer, savedHosts: model.savedHosts.allHosts)
            {
                // Swap the sheet's content (same sheet, no dismiss/present race).
                pairingSheet = .confirm(PendingPairing(offer: offer, kind: kind))
            } else {
                attemptPairing(
                    PendingPairing(offer: offer, kind: .newHost), password: nil, fromPassword: false)
            }
        } catch {
            pairingSheet = .paste(error: "That link doesn't look right.")
        }
    }

    /// One attempt at a time (S1): the token disables Connect and admits only its own
    /// completion; a newer attempt supersedes an older one (upstream cancels the older
    /// question, host-confirmation.ts ask()).
    private func attemptPairing(_ pending: PendingPairing, password: String?, fromPassword: Bool) {
        let attempt = UUID()
        pairingAttempt = attempt
        Task {
            let outcome = await model.connectRelay(offer: pending.offer, password: password)
            guard pairingAttempt == attempt else { return }
            pairingAttempt = nil
            switch outcome {
            case .connected:
                pairingSheet = nil
            case .passwordRequired:
                // S2: after a submitted password, come back fresh with the reason's own words.
                let error = fromPassword ? "Incorrect password." : nil
                pairingSheet = .password(
                    PendingPairing(offer: pending.offer, kind: pending.kind), error: error)
            case .failed(let message):
                // S6: connect failures land back on the paste sheet, error visible.
                pairingSheet = .paste(error: message)
            }
        }
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
