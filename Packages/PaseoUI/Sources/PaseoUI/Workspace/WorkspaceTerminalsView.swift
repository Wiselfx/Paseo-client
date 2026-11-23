#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// The "Terminal" page of the workspace panel (`WorkspacePanel`).
///
/// Chips along the top switch between the workspace's terminals (or create one); the body is a
/// SwiftTerm-backed emulator fed by `TerminalsStore`'s byte stream; below it, the workspace's
/// configured `paseo.json` scripts (start/stop, lifecycle, health, port). Everything talks to
/// the daemon through `session.terminals` — never through the client directly.
struct WorkspaceTerminalsView: View {
    let session: HostSession
    let workspace: WorkspaceDescriptor
    /// A terminal to select on appear, e.g. from a notification tap. Nil keeps the usual
    /// first-terminal selection.
    var initialTerminalId: String? = nil
    /// Full screen hides everything but the terminal: the panel's chrome (owned by the panel),
    /// the chip bar and the scripts.
    @Binding var isFullScreen: Bool

    @State private var selectedTerminalId: String?
    @State private var isCreating = false
    @State private var busyScripts: Set<String> = []
    /// Recently selected terminal ids, most recent last. Every one of them stays mounted in the
    /// stage, so a tab switch neither rebuilds an emulator nor asks the host for a fresh snapshot
    /// (upstream `terminal-performance.md`: "Retained terminal tabs in the focused workspace keep
    /// their streams").
    @State private var mountedTerminalIds: [String] = []
    /// The terminal the crossfade just left. It stays opaque underneath while the incoming one
    /// fades in — which is what makes the switch a crossfade instead of a dip to the canvas — and
    /// is released when the fade ends.
    @State private var outgoingTerminalId: String?
    /// One reattach counter per terminal: bumping it builds a fresh emulator and resubscribes.
    @State private var reattachCounts: [String: Int] = [:]
    /// The last line of a terminal whose process ended, per terminal id.
    @State private var exitMessages: [String: String] = [:]
    /// Last viewed time per terminal id (milliseconds), for the activity unread dot. In memory
    /// only; the daemon's activity pushes are what actually updates it.
    @State private var lastViewed: [String: Double] = [:]
    @State private var linkedFile: TerminalLinkedFile?
    @State private var serviceURLSheet: BrowserTarget?
    /// The service URL waiting on the `ask` confirmation (Settings → Terminal).
    @State private var pendingServiceURL: URL?
    @AppStorage(ServiceUrlBehavior.storageKey) private var serviceUrlBehavior = ServiceUrlBehavior.ask.rawValue
    @State private var renameTarget: TerminalInfo?
    @State private var renameText = ""
    @State private var closeCandidate: TerminalInfo?
    /// "Attach a file" from the key bar: the action sheet, the pickers, and the last upload's
    /// result toast.
    @State private var showAttachMenu = false
    @State private var showPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showFileImporter = false

    @Environment(\.openURL) private var openURL
    @Environment(\.toast) private var toast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Upstream keeps the four most recently used terminals' streams alive: "The retained-panel
    /// LRU bounds the number of live streams" (`terminal-performance.md`).
    private static let maxMountedTerminals = 4

    /// `Motion.fade`'s duration: how long the terminal a switch left behind stays opaque under the
    /// incoming one.
    private static let crossfadeMilliseconds = 200

    private var store: TerminalsStore { session.terminals }
    private var workspaceId: String { workspace.id }
    private var checkout: CheckoutStore { session.checkout(for: workspace) }

    var body: some View {
        let terminals = orderedTerminals
        let ids = terminals.map(\.id)
        let scripts = store.scripts(in: workspaceId)
        let isLoadingScripts = store.loadingScriptWorkspaces.contains(workspaceId)
        let fullScreen = isFullScreen && !mountedTerminals.isEmpty
        VStack(spacing: 0) {
            if let error = store.error {
                TerminalErrorBanner(
                    message: error, onRetry: reopen, onDismiss: { store.clearError() })
            }
            if !fullScreen {
                TerminalChipBar(
                    terminals: terminals,
                    selectedId: selectedTerminalId,
                    dotStates: dotStates(for: terminals),
                    isCreating: isCreating,
                    onSelect: { select($0) },
                    onRename: beginRename,
                    onClose: requestClose,
                    onCreate: createTerminal,
                    onEnterFullScreen: { setFullScreen(true) })
                ClaudeDivider()
            }
            TerminalStage(
                store: store,
                uploader: session.fileUploader,
                mounted: mountedTerminals,
                selectedTerminalId: selectedTerminalId,
                outgoingTerminalId: outgoingTerminalId,
                exitMessage: selectedTerminalId.flatMap { exitMessages[$0] },
                isSupported: store.isSupported,
                hasTerminals: !terminals.isEmpty,
                onExit: { recordExit($0, for: $1) },
                onOutput: markViewedIfChanged,
                onOpenLink: handleOpenLink,
                onAttach: { showAttachMenu = true },
                onCreate: createTerminal,
                onReattach: reattach,
                onDismissExit: dismissExit)
            .overlay(alignment: .topTrailing) {
                if fullScreen {
                    TerminalFullScreenButton(isFullScreen: true) { setFullScreen(false) }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .padding(Space.sm)
                        .transition(.opacity)
                }
            }
            if !fullScreen, !scripts.isEmpty || isLoadingScripts {
                ClaudeDivider()
                WorkspaceScriptsSection(
                    scripts: scripts,
                    terminalIds: Set(ids),
                    busy: busyScripts,
                    isLoading: isLoadingScripts,
                    onOpenService: openServiceURL,
                    onShowTerminal: { select($0) },
                    onToggle: toggle,
                    onRestart: restart)
            }
        }
        // One canvas for the whole workspace panel: the terminal page sits on the panel fill,
        // and the emulator's own background matches it (E2b §3).
        .background(Palette.panel)
        .paseoFeedback(.light, trigger: isCreating) { _, new in new }
        .paseoFeedback(.light, trigger: busyScripts) { old, new in new.count > old.count }
        .task {
            await store.open(workspaceId: workspaceId, cwd: workspace.cwd)
            guard !Task.isCancelled else { return }
            markCurrentViewed()
            syncFocusedTerminal()
        }
        .onAppear {
            if selectedTerminalId == nil || !ids.contains(selectedTerminalId ?? "") {
                select(preferredTerminalId(from: ids))
            }
            markCurrentViewed()
            syncFocusedTerminal()
        }
        // The focused terminal rides the presence heartbeat, so the daemon clears a terminal's
        // `needs_input`/`finished` attention once a visible client is looking at it
        // (docs/terminal-activity.md). Upstream sets it from the focused pane's active tab and
        // clears it when that route loses focus
        // (packages/app/src/screens/workspace/workspace-screen.tsx:1505-1526).
        .onDisappear {
            session.hostSettings.updateTerminalFocus(nil)
        }
        .onChange(of: scenePhase) { _, phase in
            session.hostSettings.updateTerminalFocus(phase == .active ? selectedTerminalId : nil)
        }
        .onChange(of: ids) { _, newIds in
            mountedTerminalIds.removeAll { !newIds.contains($0) }
            exitMessages = exitMessages.filter { newIds.contains($0.key) }
            reattachCounts = reattachCounts.filter { newIds.contains($0.key) }
            if let selectedTerminalId, newIds.contains(selectedTerminalId) { return }
            select(preferredTerminalId(from: newIds))
            markCurrentViewed()
        }
        .onChange(of: selectedTerminalId) { _, _ in
            markCurrentViewed()
            syncFocusedTerminal()
        }
        .confirmationDialog(
            "Attach a file",
            isPresented: $showAttachMenu,
            titleVisibility: .hidden
        ) {
            Button("Photos…") { showPhotoPicker = true }
            Button("Files…") { showFileImporter = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        // The upload runs in its own task, so resetting the selection does not cancel it.
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { await attachPhoto(item) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            Task {
                // Off the main actor (`PickedFileLoader`): this task inherits the main actor, so
                // `Data(contentsOf:)` here froze the panel for the length of the read.
                switch await PickedFileLoader.load(url, maxBytes: ConversationUpload.maxBytes) {
                case .success(let file):
                    await attach(
                        data: file.data, fileName: url.lastPathComponent, mimeType: file.mimeType)
                case .failure(.tooLarge):
                    showToast("That file is over 50 MB — too large to attach.")
                case .failure(.unopenable), .failure(.unreadable):
                    showToast("Couldn't read that file.")
                }
            }
        }
        .alert("Rename terminal", item: $renameTarget) { _ in
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") { commitRename() }
        } message: { _ in
            Text("Choose a name for this terminal.")
        }
        .confirmationDialog(
            closeCandidate.map { "Close “\($0.displayName)”?" } ?? "Close terminal?",
            item: $closeCandidate,
            titleVisibility: .visible) { candidate in
            Button("Close terminal", role: .destructive) { commitClose(candidate) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Any running process in this terminal will be stopped immediately.")
        }
        .confirmationDialog(
            "Open service URL",
            item: $pendingServiceURL,
            titleVisibility: .visible) { url in
            Button("In Paseo") { serviceURLSheet = BrowserTarget(url: url) }
            Button("External browser") { openURL(url) }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text("Open \(url.absoluteString)?")
        }
        .sheet(item: $linkedFile) { target in
            WorkspaceTerminalFileSheet(checkout: checkout, target: target)
                .presentationDetents([.large])
        }
        .fullScreenCover(item: $serviceURLSheet) { target in
            SafariView(url: target.url).ignoresSafeArea()
        }
    }

    /// Full screen in and out with one layout animation, so the grid resizes once, to the end
    /// size, instead of following every step.
    private func setFullScreen(_ value: Bool) {
        withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
            isFullScreen = value
        }
    }

    /// Follows Settings → Terminal → Clicking a script's service URL: in-app
    /// (SafariView), external (`openURL`), or ask (confirmationDialog above).
    /// Wording is upstream's (`serviceUrl.title/message/inPaseo/externalBrowser`, en.ts:2019-2022).
    private func openServiceURL(_ url: URL) {
        switch ServiceUrlBehavior(rawValue: serviceUrlBehavior) ?? .ask {
        case .inApp: serviceURLSheet = BrowserTarget(url: url)
        case .external: openURL(url)
        case .ask: pendingServiceURL = url
        }
    }

    private func markCurrentViewed() {
        guard let selectedTerminalId else { return }
        lastViewed[selectedTerminalId] = Date.now.timeIntervalSince1970 * 1000
    }

    /// Reports the terminal on screen (nil when there is none, or the app is not active) to the
    /// host's presence heartbeat. Focus changes send one immediately; the 15 s heartbeat repeats it.
    private func syncFocusedTerminal() {
        guard scenePhase == .active else { return }
        session.hostSettings.updateTerminalFocus(selectedTerminalId)
    }

    /// Live output arrived for a terminal. `lastViewed` is only written when the tab's dot would
    /// actually change: a build burst must not re-evaluate the page for a dot that is already
    /// idle. The coordinator already caps this at one call per half second.
    private func markViewedIfChanged(_ terminalId: String) {
        guard terminalId == selectedTerminalId,
            let terminal = store.terminals(in: workspaceId).first(where: { $0.id == terminalId }),
            isUnread(terminal)
        else { return }
        lastViewed[terminalId] = Date.now.timeIntervalSince1970 * 1000
    }

    /// Daemon activity newer than the last time this device looked at the terminal.
    private func isUnread(_ terminal: TerminalInfo) -> Bool {
        guard terminal.activityBucket == nil else { return false }
        guard let changedAt = terminal.activity?.changedAt, changedAt > 0 else { return false }
        return changedAt > (lastViewed[terminal.id] ?? 0)
    }

    /// Selects a terminal and keeps it at the front of the retained list, so the four most
    /// recently used emulators stay mounted and keep applying output.
    private func select(_ id: String?) {
        guard id != selectedTerminalId else { return }
        let previous = selectedTerminalId
        if let id {
            mountedTerminalIds.removeAll { $0 == id }
            mountedTerminalIds.append(id)
            while mountedTerminalIds.count > Self.maxMountedTerminals {
                mountedTerminalIds.removeFirst()
            }
        }
        selectedTerminalId = id
        outgoingTerminalId = previous
        guard let previous, !reduceMotion else {
            // Nothing to sit under: with Reduce Motion there is no fade to hide, so the outgoing
            // terminal goes dark at once.
            outgoingTerminalId = nil
            return
        }
        // Holds the previous terminal opaque for exactly the length of the crossfade, then lets it
        // go: a hidden emulator must not keep rendering under the visible one.
        Task {
            try? await Task.sleep(for: .milliseconds(Self.crossfadeMilliseconds))
            guard outgoingTerminalId == previous else { return }
            outgoingTerminalId = nil
        }
    }

    /// The requested terminal when it exists, else the first one. The request wins even
    /// after the list arrives late (a notification tap can race the terminal list load).
    private func preferredTerminalId(from ids: [String]) -> String? {
        if let initialTerminalId, ids.contains(initialTerminalId) { return initialTerminalId }
        return ids.first
    }

    // MARK: Attach a file

    /// T14 (`file.upload`, 50 MB cap), then the remote path is typed into the focused terminal
    /// shell-quoted. Errors surface as a toast; oversized files are rejected before the RPC.
    private func attach(data: Data, fileName: String, mimeType: String) async {
        guard data.count <= ConversationUpload.maxBytes else {
            showToast("That file is over 50 MB — too large to attach.")
            return
        }
        let attachment = await session.fileUploader.upload(
            data: data, fileName: fileName, mimeType: mimeType)
        if let attachment {
            if let terminalId = selectedTerminalId {
                store.sendInput(Self.shellQuote(attachment.path), to: terminalId)
                showToast("Uploaded \(attachment.fileName)")
            } else {
                showToast("Uploaded \(attachment.fileName) — no terminal focused, path not inserted")
            }
        } else if let error = session.fileUploader.error {
            showToast(error)
        }
    }

    /// The picked photo's original bytes, with the file name and MIME type from its content type.
    private func attachPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            showToast("Couldn't read that photo.")
            return
        }
        let type = item.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
        await attach(
            data: data,
            fileName: "photo.\(type.preferredFilenameExtension ?? "jpg")",
            mimeType: type.preferredMIMEType ?? "image/jpeg")
    }

    /// Single-quote for POSIX shells: `abc'def` → `'abc'\''def'`.
    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacing("'", with: "'\\''") + "'"
    }

    private func showToast(_ text: String) {
        toast?.show(text)
    }

    // MARK: Terminals

    /// Newest first when the daemon sent timestamps; otherwise the daemon's order.
    private var orderedTerminals: [TerminalInfo] {
        let all = store.terminals(in: workspaceId)
        return all.sorted { lhs, rhs in
            switch (lhs.createdAt.flatMap(PaseoDate.parse), rhs.createdAt.flatMap(PaseoDate.parse)) {
            case let (left?, right?): return left > right
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.name < rhs.name
            }
        }
    }

    private func beginRename(_ terminal: TerminalInfo) {
        renameText = terminal.displayName
        renameTarget = terminal
    }

    /// Close with confirmation only when the daemon's activity says a process is running.
    private func requestClose(_ terminal: TerminalInfo) {
        let running = terminal.activity?.state == .working || terminal.activityBucket == .running
        if running {
            closeCandidate = terminal
        } else {
            commitClose(terminal)
        }
    }

    private func commitClose(_ target: TerminalInfo) {
        Task {
            let ok = await store.killTerminal(target.id)
            if ok { Haptics.light() } else { Haptics.failure() }
        }
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        renameTarget = nil
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task {
            let ok = await store.renameTerminal(target.id, to: title, in: workspaceId)
            if ok { Haptics.light() } else { Haptics.failure() }
        }
    }

    private func createTerminal() {
        guard !isCreating else { return }
        isCreating = true
        Task {
            let created = await store.createTerminal(in: workspaceId, cwd: workspace.cwd)
            isCreating = false
            if let created { select(created.id) }
        }
    }

    private func dotStates(for terminals: [TerminalInfo]) -> [String: StatusDot.State] {
        Dictionary(
            terminals.map { ($0.id, dotKind(for: $0)) },
            uniquingKeysWith: { first, _ in first })
    }

    private func dotKind(for terminal: TerminalInfo) -> StatusDot.State {
        switch terminal.activityBucket {
        case .needsInput: return .attention
        case .attention: return .idle
        case .running: return .running
        case nil:
            // Daemon activity arrived since the viewer last looked at this tab.
            return isUnread(terminal) ? .unread : .idle
        }
    }

    private var mountedTerminals: [MountedTerminal] {
        mountedTerminalIds.map { id in
            MountedTerminal(terminalId: id, generation: reattachCounts[id] ?? 0)
        }
    }

    /// Remembers why a terminal ended, per terminal, so a tab switch never shows the wrong one.
    private func recordExit(_ message: String?, for terminalId: String) {
        exitMessages[terminalId] = exitLine(for: message)
    }

    private func handleOpenLink(_ target: TerminalLinkTarget) {
        switch target {
        case .localFile(let path, let line, let col):
            linkedFile = TerminalLinkedFile(path: path, line: line, col: col)
        case .url(let url):
            openURL(url)
        case .unhandled:
            Haptics.failure()
        }
    }

    private func exitLine(for error: String?) -> String {
        guard let error else { return "The terminal ended." }
        return "\(error)\nThe process may still be running."
    }

    /// A fresh emulator and a fresh subscription, at the same grid.
    private func reattach(_ terminalId: String) {
        Haptics.selection()
        exitMessages[terminalId] = nil
        reattachCounts[terminalId, default: 0] += 1
    }

    private func dismissExit(_ terminalId: String) {
        exitMessages[terminalId] = nil
    }

    // MARK: Scripts

    /// Restart = stop then start, one action. No confirmation: the script is designed to be
    /// bounced.
    private func restart(_ script: WorkspaceScript) {
        Task {
            busyScripts.insert(script.scriptName)
            if script.lifecycle == .running {
                _ = await store.stopScript(script.scriptName, in: workspaceId)
            }
            _ = await store.startScript(script.scriptName, in: workspaceId)
            busyScripts.remove(script.scriptName)
        }
    }

    private func toggle(_ script: WorkspaceScript) {
        let isRunning = script.lifecycle == .running
        busyScripts.insert(script.scriptName)
        Task {
            if isRunning {
                _ = await store.stopScript(script.scriptName, in: workspaceId)
            } else {
                _ = await store.startScript(script.scriptName, in: workspaceId)
            }
            busyScripts.remove(script.scriptName)
        }
    }

    // MARK: Errors

    /// Reopening the directory clears the error on success, so dismiss and retry do the same
    /// thing on the store side.
    private func reopen() {
        Task { await store.open(workspaceId: workspaceId, cwd: workspace.cwd) }
    }
}
#endif
