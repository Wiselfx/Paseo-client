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

    @State private var selectedTerminalId: String?
    @State private var isCreating = false
    @State private var busyScripts: Set<String> = []
    @State private var exitMessage: String?
    @State private var exitGeneration = 0
    /// Last viewed time per terminal id (milliseconds), for the activity unread dot. In memory
    /// only; the daemon's activity pushes are what actually updates it.
    @State private var lastViewed: [String: Double] = [:]
    @State private var linkedFile: TerminalLinkedFile?
    @State private var serviceURLSheet: URL?
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
    @State private var showFileImporter = false

    @Environment(\.openURL) private var openURL
    @Environment(\.toast) private var toast


    private var store: TerminalsStore { session.terminals }
    private var workspaceId: String { workspace.id }
    private var checkout: CheckoutStore { session.checkout(for: workspace) }

    var body: some View {
        let terminals = orderedTerminals
        VStack(spacing: 0) {
            if let error = store.error { errorBanner(error) }
            terminalPicker(terminals)
            ClaudeDivider()
            terminalArea(terminals)
            let scripts = store.scripts(in: workspaceId)
            if !scripts.isEmpty || store.loadingScriptWorkspaces.contains(workspaceId) {
                ClaudeDivider()
                scriptsSection(scripts)
            }
        }
        .background(Palette.background)
        .task {
            await store.open(workspaceId: workspaceId, cwd: workspace.cwd)
            guard !Task.isCancelled else { return }
            markCurrentViewed()
        }
        .onAppear {
            if selectedTerminalId == nil || !terminalIds.contains(selectedTerminalId ?? "") {
                selectedTerminalId = preferredTerminalId(from: terminalIds)
            }
            markCurrentViewed()
        }
        .onChange(of: terminalIds) { _, ids in
            if let selectedTerminalId, ids.contains(selectedTerminalId) { return }
            selectedTerminalId = preferredTerminalId(from: ids)
            exitMessage = nil
            markCurrentViewed()
        }
        .onChange(of: selectedTerminalId) { _, _ in markCurrentViewed() }
        .confirmationDialog(
            "Attach a file",
            isPresented: $showAttachMenu,
            titleVisibility: .hidden
        ) {
            Button("Photos…") { showPhotoPicker = true }
            Button("Files…") { showFileImporter = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(onPick: { data, fileName, mimeType in
                showPhotoPicker = false
                Task { await attach(data: data, fileName: fileName, mimeType: mimeType) }
            }, onCancel: {
                showPhotoPicker = false
            })
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            Task {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    showToast("Couldn't read that file.")
                    return
                }
                let ext = url.pathExtension.lowercased()
                let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType
                    ?? "application/octet-stream"
                await attach(data: data, fileName: url.lastPathComponent, mimeType: mimeType)
            }
        }
        .alert("Rename terminal", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") { commitRename() }
        } message: {
            Text("Choose a name for this terminal.")
        }
        .confirmationDialog(
            closeCandidate.map { "Close “\(displayName($0))”?" } ?? "Close terminal?",
            isPresented: Binding(
                get: { closeCandidate != nil },
                set: { if !$0 { closeCandidate = nil } }),
            titleVisibility: .visible) {
            Button("Close terminal", role: .destructive) { commitClose() }
            Button("Cancel", role: .cancel) { closeCandidate = nil }
        } message: {
            Text("Any running process in this terminal will be stopped immediately.")
        }
        .confirmationDialog(
            "Open service URL",
            isPresented: Binding(
                get: { pendingServiceURL != nil },
                set: { if !$0 { pendingServiceURL = nil } }),
            titleVisibility: .visible) {
            Button("In Paseo") {
                if let url = pendingServiceURL { serviceURLSheet = url }
                pendingServiceURL = nil
            }
            Button("External browser") {
                if let url = pendingServiceURL { openURL(url) }
                pendingServiceURL = nil
            }
            Button("Cancel", role: .cancel) { pendingServiceURL = nil }
        } message: {
            Text(pendingServiceURL.map { "Open \($0.absoluteString)?" } ?? "")
        }
        .sheet(item: $linkedFile) { target in
            WorkspaceTerminalFileSheet(checkout: checkout, target: target)
                .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: Binding(
            get: { serviceURLSheet != nil },
            set: { if !$0 { serviceURLSheet = nil } })) {
            if let url = serviceURLSheet {
                SafariView(url: url).ignoresSafeArea()
            }
        }
    }

    /// Follows Settings → Terminal → Clicking a script's service URL: in-app
    /// (SafariView), external (`openURL`), or ask (confirmationDialog above).
    /// Wording is upstream's (`serviceUrl.title/message/inPaseo/externalBrowser`, en.ts:2019-2022).
    private func openServiceURL(_ url: URL) {
        switch ServiceUrlBehavior(rawValue: serviceUrlBehavior) ?? .ask {
        case .inApp: serviceURLSheet = url
        case .external: openURL(url)
        case .ask: pendingServiceURL = url
        }
    }

    private func markCurrentViewed() {
        guard let selectedTerminalId else { return }
        lastViewed[selectedTerminalId] = Date().timeIntervalSince1970 * 1000
    }

    /// The requested terminal when it exists, else the first one. The request wins even
    /// after the list arrives late (a notification tap can race the terminal list load).
    private func preferredTerminalId(from ids: [String]) -> String? {
        if let initialTerminalId, ids.contains(initialTerminalId) { return initialTerminalId }
        return ids.first
    }

    // MARK: Attach a file

    /// The key bar's progress row, straight off the T14 uploader (one upload at a time).
    private var uploadSnapshot: TerminalUploadSnapshot? {
        let uploader = session.fileUploader
        guard uploader.isUploading, let name = uploader.fileName else { return nil }
        return TerminalUploadSnapshot(fileName: name, progress: uploader.progress)
    }

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

    /// Single-quote for POSIX shells: `abc'def` → `'abc'\''def'`.
    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func showToast(_ text: String) {
        toast?.show(text)
    }

    // MARK: Terminals

    private var terminalIds: [String] {
        orderedTerminals.map(\.id)
    }

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

    private func displayName(_ terminal: TerminalInfo) -> String {
        if let title = terminal.title, !title.isEmpty, title != terminal.name {
            return title
        }
        return terminal.name
    }

    private func terminalPicker(_ terminals: [TerminalInfo]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(terminals) { terminal in
                    terminalChip(terminal)
                }
                newTerminalButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 48)
    }

    private func terminalChip(_ terminal: TerminalInfo) -> some View {
        let isSelected = terminal.id == selectedTerminalId
        return Button {
            Haptics.selection()
            if selectedTerminalId != terminal.id {
                selectedTerminalId = terminal.id
                exitMessage = nil
                markCurrentViewed()
            }
        } label: {
            HStack(spacing: 6) {
                PaseoStatusDot(kind: dotKind(for: terminal))
                Text(displayName(terminal))
                    .font(.paseo(.footnote))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.md)
            .frame(minHeight: 44)
            .background(isSelected ? Palette.chip : Color.clear, in: .capsule)
            .overlay(
                Capsule().strokeBorder(
                    Palette.cardBorder, lineWidth: isSelected ? 0 : 0.5))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Terminal \(displayName(terminal))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .contextMenu {
            Button("Rename…", systemImage: "pencil") {
                renameText = displayName(terminal)
                renameTarget = terminal
            }
            Button("Close", systemImage: "xmark", role: .destructive) {
                requestClose(terminal)
            }
        }
    }

    /// Close with confirmation only when the daemon's activity says a process is running.
    private func requestClose(_ terminal: TerminalInfo) {
        let running = terminal.activity?.state == .working || terminal.activityBucket == .running
        if running {
            closeCandidate = terminal
        } else {
            Task {
                let ok = await store.killTerminal(terminal.id)
                if ok { Haptics.success() } else { Haptics.failure() }
            }
        }
    }

    private func commitClose() {
        guard let target = closeCandidate else { return }
        closeCandidate = nil
        Task {
            let ok = await store.killTerminal(target.id)
            if ok { Haptics.success() } else { Haptics.failure() }
        }
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        renameTarget = nil
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task {
            let ok = await store.renameTerminal(target.id, to: title, in: workspaceId)
            if ok { Haptics.success() } else { Haptics.failure() }
        }
    }

    private func dotKind(for terminal: TerminalInfo) -> PaseoStatusDot.Kind {
        switch terminal.activityBucket {
        case .needsInput: return .needsInput
        case .attention: return .done
        case .running: return .running
        case nil:
            // Daemon activity arrived since the viewer last looked at this tab.
            if let changedAt = terminal.activity?.changedAt, changedAt > 0,
                changedAt > (lastViewed[terminal.id] ?? 0)
            {
                return .unread
            }
            return .idle
        }
    }

    private var newTerminalButton: some View {
        Button {
            Haptics.selection()
            guard !isCreating else { return }
            isCreating = true
            Task {
                let created = await store.createTerminal(in: workspaceId, cwd: workspace.cwd)
                isCreating = false
                if let created {
                    selectedTerminalId = created.id
                    exitMessage = nil
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isCreating {
                    ProgressView().controlSize(.mini).tint(Palette.secondaryInk)
                } else {
                    Image(systemName: "plus")
                        .font(.glyph(.small, weight: .medium))
                }
                Text("New").font(.paseo(.footnote))
            }
            .padding(.horizontal, Space.md)
            .frame(minHeight: 44)
            .foregroundStyle(Palette.ink)
            .overlay(
                Capsule().strokeBorder(Palette.cardBorder, lineWidth: 0.5))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
        .accessibilityLabel("New terminal")
    }

    private func terminalArea(_ terminals: [TerminalInfo]) -> some View {
        ZStack {
            if !store.isSupported {
                statusMessage(
                    "Update the host to view terminals.",
                    detail: "This host predates the terminal replay protocol.")
            } else if let selectedTerminalId, terminals.contains(where: { $0.id == selectedTerminalId }) {
                PaseoTerminalView(
                    store: store,
                    terminalId: selectedTerminalId,
                    onExit: { message in exitMessage = exitLine(for: message) },
                    onOutput: { markCurrentViewed() },
                    onOpenLink: handleOpenLink,
                    upload: uploadSnapshot,
                    onAttach: {
                        Haptics.selection()
                        showAttachMenu = true
                    },
                    onCancelUpload: { session.fileUploader.cancel() })
                .id("\(selectedTerminalId)-\(exitGeneration)")
                if let exitMessage {
                    exitOverlay(exitMessage)
                }
            } else if terminals.isEmpty {
                emptyState
            } else {
                // The selected id is stale during the same frame the data refreshes.
                LoadingState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyState(
            systemImage: "apple.terminal",
            title: "No terminals yet",
            message: "Start one to run commands in this workspace.",
            action: (title: "New terminal", run: {
                Haptics.selection()
                guard !isCreating else { return }
                isCreating = true
                Task {
                    let created = await store.createTerminal(in: workspaceId, cwd: workspace.cwd)
                    isCreating = false
                    if let created {
                        selectedTerminalId = created.id
                        exitMessage = nil
                    }
                }
            }))
        .padding(.horizontal, Space.xxxl)
    }

    private func statusMessage(_ title: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "info")
                .font(.glyph(.large, weight: .light))
                .foregroundStyle(Palette.secondaryInk)
            Text(title)
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
    }

    private func handleOpenLink(_ target: TerminalLinkTarget) {
        switch target {
        case .localFile(let path, let line, let col):
            Haptics.selection()
            linkedFile = TerminalLinkedFile(path: path, line: line, col: col)
        case .url(let url):
            Haptics.selection()
            openURL(url)
        case .unhandled:
            Haptics.failure()
        }
    }

    private func exitLine(for error: String?) -> String {
        guard let error else { return "The terminal ended." }
        return "\(error)\nThe process may still be running."
    }

    private func exitOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button {
                    Haptics.selection()
                    exitMessage = nil
                    exitGeneration += 1
                } label: {
                    Text("Reattach")
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.background)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .background(Palette.ink, in: .capsule)
                }
                .buttonStyle(.plain)
                Button {
                    exitMessage = nil
                } label: {
                    Text("Dismiss")
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .overlay(Capsule().strokeBorder(Palette.cardBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.cardBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
        .padding(.horizontal, 32)
    }

    // MARK: Scripts

    private func scriptsSection(_ scripts: [WorkspaceScript]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Scripts")
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: 8)
                if store.loadingScriptWorkspaces.contains(workspaceId) {
                    ProgressView().controlSize(.small).tint(Palette.secondaryInk)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(scripts) { script in
                        if script.id != scripts.first?.id { ClaudeDivider().padding(.leading, 40) }
                        scriptRow(script)
                    }
                }
            }
            .frame(maxHeight: 168)
        }
        .padding(.bottom, 4)
    }

    private func scriptRow(_ script: WorkspaceScript) -> some View {
        let serviceURL = script.lifecycle == .running ? script.preferredURL.flatMap(URL.init(string:)) : nil
        return HStack(spacing: 12) {
            PaseoStatusDot(kind: scriptDotKind(script))
            VStack(alignment: .leading, spacing: 2) {
                Text(script.scriptName)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(scriptSubtitle(script))
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let serviceURL {
                Button {
                    Haptics.selection()
                    openServiceURL(serviceURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.glyph(.regular, weight: .regular))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: 36, height: 36)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View service \(script.scriptName)")
                .contextMenu {
                    Button("View service", systemImage: "arrow.up.right.square") {
                        openServiceURL(serviceURL)
                    }
                    Button("Copy URL", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = serviceURL.absoluteString
                        Haptics.success()
                    }
                }
            }
            if let terminalId = script.terminalId, terminalIds.contains(terminalId) {
                Button {
                    Haptics.selection()
                    selectedTerminalId = terminalId
                    exitMessage = nil
                } label: {
                    Text("View")
                        .font(.paseo(.footnote, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(minHeight: 30)
                        .padding(.horizontal, 12)
                        .overlay(Capsule().strokeBorder(Palette.cardBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show terminal for \(script.scriptName)")
            }
            scriptActionButton(script)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .contextMenu {
            Button("Restart", systemImage: "arrow.clockwise") {
                Task { await restart(script) }
            }
            let urlTargets = scriptURLTargets(script)
            if !urlTargets.isEmpty {
                Menu("Choose URL", systemImage: "link") {
                    ForEach(urlTargets) { target in
                        Button {
                            UIPasteboard.general.string = target.url
                            Haptics.success()
                        } label: {
                            VStack(alignment: .leading) {
                                Text("Copy \(target.title) URL")
                                Text(target.hostLabel)
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    }
                }
            }
            if let serviceURL = script.preferredURL {
                Button("Copy URL", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = serviceURL
                    Haptics.success()
                }
            }
        }
    }

    /// One URL the daemon advertises for a running service. Follows upstream's COMPAT split:
    /// `localProxyUrl` (or a loopback-looking `proxyUrl`) is "Memorable", `publicProxyUrl` (or a
    /// non-loopback `proxyUrl`) is "Reverse proxy", and `port` yields the direct URL. Deduped by
    /// URL, and shown only when the script is a running service.
    private struct ScriptURLTarget: Identifiable {
        let kind: String
        let title: String
        let url: String
        let hostLabel: String
        var id: String { kind }
    }

    private func scriptURLTargets(_ script: WorkspaceScript) -> [ScriptURLTarget] {
        guard script.type == .service, script.lifecycle == .running else { return [] }
        func isLoopbackURL(_ url: String) -> Bool {
            guard let host = URLComponents(string: url)?.host?.lowercased() else { return true }
            return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
        }
        var targets: [ScriptURLTarget] = []
        func add(_ kind: String, title: String, url: String?) {
            guard let url, !url.isEmpty, !targets.contains(where: { $0.url == url }) else { return }
            let host = URLComponents(string: url)?.host ?? url
            targets.append(ScriptURLTarget(kind: kind, title: title, url: url, hostLabel: host))
        }
        let local = script.localProxyUrl
            ?? (script.proxyUrl.map(isLoopbackURL) == true ? script.proxyUrl : nil)
        let pub = script.publicProxyUrl
            ?? (script.proxyUrl.map { !isLoopbackURL($0) } == true ? script.proxyUrl : nil)
        add("public", title: "Reverse proxy", url: pub)
        add("paseo", title: "Memorable", url: local)
        // No connection info on this client to build a true direct URL; localhost is the
        // honest default (matches upstream when there is no directTcp connection).
        if let port = script.port {
            add("direct", title: "Direct", url: "http://localhost:\(port)")
        }
        return targets
    }

    /// Restart = stop then start, one action. No confirmation: the script is designed to be
    /// bounced.
    private func restart(_ script: WorkspaceScript) async {
        Haptics.selection()
        busyScripts.insert(script.scriptName)
        if script.lifecycle == .running {
            _ = await store.stopScript(script.scriptName, in: workspaceId)
        }
        _ = await store.startScript(script.scriptName, in: workspaceId)
        busyScripts.remove(script.scriptName)
    }

    private func scriptSubtitle(_ script: WorkspaceScript) -> String {
        var parts: [String] = []
        switch script.lifecycle {
        case .running: parts.append("Running")
        case .stopped: parts.append("Stopped")
        case .unknown: parts.append("Unknown")
        }
        switch script.health {
        case .healthy: parts.append("healthy")
        case .unhealthy: parts.append("unhealthy")
        case .unknown, .none: break
        }
        if let port = script.port { parts.append(":\(port)") }
        if script.lifecycle == .stopped, let code = script.exitCode, code != 0 {
            parts.append("exit \(code)")
        }
        return parts.joined(separator: " · ")
    }

    private func scriptDotKind(_ script: WorkspaceScript) -> PaseoStatusDot.Kind {
        switch script.lifecycle {
        case .running:
            return script.health == .unhealthy ? .failed : .running
        case .stopped:
            return (script.exitCode ?? 0) != 0 ? .failed : .idle
        case .unknown:
            return .idle
        }
    }

    private func scriptActionButton(_ script: WorkspaceScript) -> some View {
        let busy = busyScripts.contains(script.scriptName)
        let isRunning = script.lifecycle == .running
        return Button {
            Haptics.selection()
            busyScripts.insert(script.scriptName)
            Task {
                if isRunning {
                    _ = await store.stopScript(script.scriptName, in: workspaceId)
                } else {
                    _ = await store.startScript(script.scriptName, in: workspaceId)
                }
                busyScripts.remove(script.scriptName)
            }
        } label: {
            Group {
                if busy {
                    ProgressView().controlSize(.small).tint(Palette.ink)
                } else {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .frame(width: 32, height: 32)
            .background(Palette.chip, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("\(isRunning ? "Stop" : "Start") \(script.scriptName)")
    }

    // MARK: Errors

    private func errorBanner(_ message: String) -> some View {
        InlineBanner(
            .failure, title: message,
            onDismiss: { store.clearError() })
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.xs)
    }
}

/// PHPicker wrapper (iOS 14+, no library-permission prompt for `.images`): one image, its
/// original bytes, file name from the content type. SwiftUI's own `.photosPicker` modifier is
/// avoided because availability varies across SDKs.
private struct PhotoPickerView: UIViewControllerRepresentable {
    var onPick: @MainActor (Data, String, String) -> Void
    var onCancel: @MainActor () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: @MainActor (Data, String, String) -> Void
        let onCancel: @MainActor () -> Void

        init(
            onPick: @escaping @MainActor (Data, String, String) -> Void,
            onCancel: @escaping @MainActor () -> Void
        ) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                Task { @MainActor in onCancel() }
                return
            }
            let provider = result.itemProvider
            let type = provider.registeredContentTypes.first { $0.conforms(to: .image) } ?? .image
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { [onPick, onCancel] data, _ in
                let ext = type.preferredFilenameExtension ?? "jpg"
                let mime = type.preferredMIMEType ?? "image/jpeg"
                if let data {
                    Task { @MainActor in onPick(data, "photo.\(ext)", mime) }
                } else {
                    Task { @MainActor in onCancel() }
                }
            }
        }
    }
}
#endif
