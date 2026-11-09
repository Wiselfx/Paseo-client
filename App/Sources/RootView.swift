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
    /// M20: a navigation link waiting for the shell (agent / workspace / host / open project).
    /// Set only after its host is the connected one, so a cold launch and a host switch both
    /// land in the same place.
    @State private var deepLinkTarget: DeepLink?
    /// A plain message for a link we cannot route (unsupported route, unknown host, no hosts).
    @State private var deepLinkMessage: String?

    /// One deep-link host question. `id` is fresh per request so re-opening the chooser for a
    /// second link always presents.
    struct HostChoice: Identifiable {
        let id = UUID()
        let link: DeepLink
        let hosts: [DeepLinkHost]
    }

    /// One pairing question or prompt. `id` is fresh per instance: a new attempt must
    /// re-present the password sheet (S2), not reuse the identity of the old one.
    struct PendingPairing: Identifiable {
        let id = UUID()
        let offer: ConnectionOffer
        let kind: HostConfirmationKind
    }

    enum PairingSheet: Identifiable {
        case scan
        case paste(error: String?)
        case confirm(PendingPairing)
        case password(PendingPairing, error: String?)
        case chooseHost(HostChoice)

        var id: String {
            switch self {
            case .scan: "scan"
            case .paste(let error): "paste.\(error ?? "")"
            case .confirm(let pending): "confirm.\(pending.id)"
            case .password(let pending, let error): "password.\(pending.id).\(error ?? "")"
            case .chooseHost(let choice): "chooseHost.\(choice.id)"
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
                    notificationTarget: $notifications.pendingTarget,
                    deepLinkTarget: $deepLinkTarget
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
            case .chooseHost(let choice):
                HostChooserSheet(hosts: choice.hosts) { host in
                    pairingSheet = nil
                    openDeepLink(choice.link, on: host)
                }
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .alert(
            deepLinkMessage ?? "",
            isPresented: Binding(
                get: { deepLinkMessage != nil },
                set: { if !$0 { deepLinkMessage = nil } })
        ) {
            Button("OK", role: .cancel) { deepLinkMessage = nil }
        }
        .onChange(of: model.relayPasswordRequest) { _, request in
            guard let request else { return }
            // S3: a saved relay host rejected the stored password; ask again here.
            // Clear the request after consuming (N6): a stale non-nil value is a trap.
            model.relayPasswordRequest = nil
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
            stagePairing(try ConnectionOffer(link: payload))
        } catch {
            pairingSheet = .paste(error: "That link doesn't look right.")
        }
    }

    /// The same path for an offer that arrived as a `paseo://` URL (M20): a pairing link is a
    /// credential, so it goes through R18's confirmation sheet and pins logic unchanged.
    private func stagePairing(_ offer: ConnectionOffer) {
        if let kind = HostConfirmation.confirmationKind(
            offer: offer, savedHosts: model.savedHosts.allHosts)
        {
            // Swap the sheet's content (same sheet, no dismiss/present race).
            pairingSheet = .confirm(PendingPairing(offer: offer, kind: kind))
        } else {
            attemptPairing(
                PendingPairing(offer: offer, kind: .newHost), password: nil, fromPassword: false)
        }
    }

    // MARK: Deep links (M20)

    /// One link from the system. Malformed and unknown links are ignored; credential links go
    /// to the pairing flow; navigation links resolve a saved host (asking when the link names
    /// none and several are saved); known-but-unsupported routes get a plain message.
    private func handleDeepLink(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .offer(let offer):
            stagePairing(offer)
        case .unsupported:
            deepLinkMessage = "This link isn't supported on this device."
        case .agent, .workspace, .host, .openProject:
            routeDeepLink(link)
        }
    }

    private func routeDeepLink(_ link: DeepLink) {
        guard let resolution = DeepLinkRouter.resolveHost(
            for: link, savedHosts: savedDeepLinkHosts)
        else { return }
        switch resolution {
        case .target(let host):
            openDeepLink(link, on: host)
        case .chooseHost(let hosts):
            pairingSheet = .chooseHost(HostChoice(link: link, hosts: hosts))
        case .unknownHost:
            // Upstream `host.daemon.picker.notFound` (en.ts:2899).
            deepLinkMessage = "Host not found"
        case .noHosts:
            // Upstream `agentPanel.unavailable.addHost` (en.ts:268).
            deepLinkMessage =
                "Add the host in Settings or open an agent on a configured server to continue."
        }
    }

    private var savedDeepLinkHosts: [DeepLinkHost] {
        // M20b: a direct host stores the daemon id it learned on its first connect, so the
        // live session's `server_info` is no longer needed as a special case here.
        model.savedHosts.allHosts.map { saved in
            DeepLinkHost(saved: saved, isCurrent: saved.id == model.connectedHostID)
        }
    }

    /// Hand the link to the shell once its host is the connected one. A different saved host
    /// is connected first (one host at a time), then the link routes; a failed connect leaves
    /// the connect screen with its own inline error.
    private func openDeepLink(_ link: DeepLink, on host: DeepLinkHost) {
        if model.connectedHostID == host.id {
            deepLinkTarget = link
            return
        }
        Task {
            await model.connectToSaved(host.id)
            // A cold launch may still be connecting to the previous host; never route a link
            // into a shell that belongs to a different daemon.
            guard model.connectedHostID == host.id, case .connected = model.phase else { return }
            deepLinkTarget = link
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
                // S2: after a submitted password, come back fresh; "Wrong password." matches
                // the daemon-reason mapping in AppModel.describe (one wording, N8).
                let error = fromPassword ? "Wrong password." : nil
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
