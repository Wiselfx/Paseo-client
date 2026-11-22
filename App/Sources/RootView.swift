import CoreSpotlight
import PaseoStore
import PaseoUI
import SwiftUI

/// The composition root: connect, then hand the live session to the ClaudeUI shell.
/// Features never know about each other; they're wired together only here.
struct RootView: View {
    @Bindable var model: AppModel
    @Bindable var notifications: NotificationCoordinator
    @Environment(\.scenePhase) private var scenePhase
    /// The system text size; Content size shifts it and Code size shifts code containers.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(ClaudeAppearance.storageKey) private var appearance = ClaudeAppearance.system.rawValue
    @AppStorage(ClaudeAccent.storageKey) private var accent = ClaudeAccent.paseo.rawValue
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
    @State private var deepLinkMessage: DeepLinkNotice?

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

    /// One deep-link message for the alert. `alert(_:item:)` needs an identity, and a fresh
    /// `id` per message presents a repeated message again.
    struct DeepLinkNotice: Identifiable {
        let id = UUID()
        let message: String
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

    private var appearanceChoice: ClaudeAppearance {
        ClaudeAppearance(rawValue: appearance) ?? .system
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

    /// Content size steps the whole shell's Dynamic Type; code size shifts code containers.
    private var contentStep: Int {
        (ClaudeTextScale.Content(rawValue: contentTextSize) ?? .medium).step
    }

    private var codeStep: Int {
        (ClaudeTextScale.Code(rawValue: codeFontSize) ?? .medium).step
    }

    private var pureBlack: Bool {
        appearanceChoice.isPureBlack
    }

    var body: some View {
        let _ = PaseoPerf.body("Root")
        Group {
            switch model.phase {
            case .setup(let status):
                if model.showsLaunchSkeleton {
                    // A saved host is connecting: the shell's first frame, never the form (§1).
                    LaunchSkeleton()
                } else if !welcomeCompleted, model.savedHostsSnapshot.isEmpty, case .idle = status {
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
                // The coordinator itself: one object for the app's lifetime, so Settings never
                // updates because the actions were re-created.
                .environment(\.notificationActions, notifications)
                .modifier(
                    AttentionDelivery(
                        session: session, scenePhase: scenePhase,
                        notifications: notifications))
                // Glance snapshot on backgrounding (G14): the widgets show what
                // the app last saw, honestly timestamped.
                .onChange(of: scenePhase) { _, phase in
                    handleScenePhase(phase, session: session)
                }

            }
        }
        .dynamicTypeSize(dynamicTypeSize.shifted(by: contentStep))
        .environment(\.codeSizeStep, codeStep)
        .environment(\.pureBlack, pureBlack)
        .environment(\.accent, ClaudeAccent(rawValue: accent) ?? .paseo)
        // Light / Dark / Pure black / System is a window trait, not a SwiftUI preference: the
        // Settings sheet is its own hosting controller and has to follow while it is open (H4 §3).
        // No `.preferredColorScheme` here: it cannot reach a presented sheet, and it cannot return
        // to the OS style at all.
        .background {
            WindowAppearance(style: UIUserInterfaceStyle(appearanceChoice))
                .frame(width: 0, height: 0)
        }
        .environment(\.hostSwitch, model.hostContext)
        .sheet(isPresented: $model.addHostRequested) {
            AddHostMethodsSheet(
                onDirect: { model.addHostRequested = false },
                onScan: { model.addHostRequested = false; pairingSheet = .scan },
                onPaste: { model.addHostRequested = false; pairingSheet = .paste(error: nil) })
        }
        .sheet(item: $pairingSheet) { sheet in
            PairingSheetContent(
                sheet: sheet, isAttempting: pairingAttempt != nil,
                hostName: { offer in displayName(for: offer) },
                onPayload: { payload in stagePairing(payload) },
                onUsePaste: { pairingSheet = .paste(error: nil) },
                onPair: { pending, password, fromPassword in
                    attemptPairing(pending, password: password, fromPassword: fromPassword)
                },
                onChooseHost: { choice, host in
                    pairingSheet = nil
                    openDeepLink(choice.link, on: host)
                })
        }
        // Launch's expensive half: the Keychain, the host migration, the snapshot, the first
        // connect. `init` stays cheap so this frame is on screen first (§1).
        .task { await model.start() }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        // A Spotlight agent result routes through the same deep-link path (G16):
        // the id carries no host, so the persisted directory resolves it.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            handleSpotlight(activity)
        }
        .alert(deepLinkMessage?.message ?? "", item: $deepLinkMessage) { _ in
            Button("OK", role: .cancel) {}
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

    /// Draft writes are coalesced (200 ms); leaving the app flushes the last keystrokes
    /// whatever screen is up (R1.A; upstream flushes its draft storage on AppState,
    /// `packages/app/src/app/_layout.tsx:997`), and writes the glance snapshot (G14).
    private func handleScenePhase(_ phase: ScenePhase, session: HostSession) {
        guard phase == .background else { return }
        DraftStore.shared.flush()
        Task { await model.publishGlanceSnapshot(session: session, force: true) }
    }

    /// A Spotlight agent result routes through the same deep-link path (G16): the id carries
    /// no host, so the persisted directory resolves it.
    private func handleSpotlight(_ activity: NSUserActivity) {
        guard
            let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
            id.hasPrefix("paseo-agent:"),
            let entry = AgentDirectory.load().agents.first(where: {
                AgentDirectory.spotlightID(for: $0.id) == id
            })
        else { return }
        routeDeepLink(.agent(serverID: entry.hostServerID, agentID: entry.id))
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
            deepLinkMessage = DeepLinkNotice(message: "This link isn't supported on this device.")
        case .agent, .workspace, .host, .openProject, .newAgent:
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
            deepLinkMessage = DeepLinkNotice(message: "Host not found")
        case .noHosts:
            // Upstream `agentPanel.unavailable.addHost` (en.ts:268).
            deepLinkMessage = DeepLinkNotice(
                message:
                    "Add the host in Settings or open an agent on a configured server to continue.")
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

}
