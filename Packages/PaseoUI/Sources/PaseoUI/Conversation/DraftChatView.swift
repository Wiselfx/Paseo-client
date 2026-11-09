#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A session that does not exist yet (UX-SPEC §3). It is the conversation surface, not a sheet:
/// the workspace name in the header, the DSH mark over a serif greeting while nothing has been
/// sent, the workspace line and the normal composer. The first send creates the agent with the
/// text and attachments as its first turn, and the shell swaps its conversation in.
struct DraftChatView: View {
    let session: HostSession
    @Bindable var draft: DraftSession
    var onOpenSidebar: () -> Void
    var onOpenPanel: (() -> Void)?
    /// No workspaces on this host: the hero asks for a project instead of offering a composer.
    var onAddProject: () -> Void
    var onCreated: (String) -> Void

    @State private var showControls = false
    @State private var focused = false
    @State private var tray: [ComposerAttachmentItem] = []
    @State private var uploadPumpRunning = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showCameraPicker = false
    @State private var viewerImage: UIImage?
    @State private var attachmentError: String?
    @State private var dictation = DictationController()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    private let typography = ClaudeTypography()

    var body: some View {
        VStack(spacing: 0) {
            header
            stage
            if needsProject {
                addProjectAction
            } else {
                workspaceLine
                composer
            }
        }
        // No background here: the shell's rounded card is the canvas (UX-SPEC §1.1).
        .foregroundStyle(ClaudePalette.ink)
        .tint(ClaudePalette.ink)
        .task { await loadCatalogue() }
        .onChange(of: session.agentControl.providers) { _, _ in seedIfNeeded() }
        .onChange(of: focused) { _, isFocused in
            if isFocused { Haptics.selection() }
        }
        .sheet(isPresented: $showControls) {
            DraftControlsSheet(session: session, draft: draft)
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraCaptureView(
                onCapture: { image in
                    showCameraPicker = false
                    guard let data = image.jpegData(compressionQuality: 1.0) else {
                        attachmentError = "Couldn't read that photo."
                        return
                    }
                    attachImageData(data, fileName: "photo-\(UUID().uuidString.prefix(8)).jpg")
                },
                onCancel: { showCameraPicker = false })
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFileImporter, allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): attachFileURLs(urls)
            case .failure(let error): attachmentError = error.localizedDescription
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { viewerImage != nil },
                set: { if !$0 { viewerImage = nil } })
        ) {
            if let image = viewerImage {
                AttachmentImageViewer(image: image)
            }
        }
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            handlePickedPhotos(items)
        }
        .onAppear {
            dictation.onDraft = { text in draft.text = text }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onOpenSidebar) {
                UnequalMenu().stroke(
                    ClaudePalette.ink.opacity(0.8),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                )
                .frame(width: 18, height: 17)
                .frame(width: 44, height: 44)
            }
            .glassEffect(in: .circle)
            .accessibilityLabel("Open sidebar")

            Text(workspaceTitle)
                .font(typography.serif(20, relativeTo: .headline))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("draft.workspace")

            if let onOpenPanel {
                Button(action: onOpenPanel) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Open workspace panel")
            } else {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
    }

    // MARK: Stage

    /// The greeting fades out the moment the first prompt leaves, replaced by the pending bubble
    /// that the new conversation will carry (§3.2).
    private var stage: some View {
        ZStack {
            if let pending = draft.pendingPrompt {
                VStack(spacing: 0) {
                    ClaudeUserBubble(text: pending, isPending: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                }
            } else {
                ClaudeHomeHero()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: draft.pendingPrompt)
    }

    private var addProjectAction: some View {
        VStack(spacing: 10) {
            Button(action: onAddProject) {
                Label("Add project", systemImage: "folder.badge.plus")
                    .font(typography.sans(16, weight: .medium))
                    .foregroundStyle(ClaudePalette.background)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(ClaudePalette.ink, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("draft.addProject")
        }
        .padding(.bottom, 40)
    }

    // MARK: Workspace line

    @ViewBuilder private var workspaceLine: some View {
        if !session.workspaceDirectory.groups.isEmpty {
            Menu {
                ForEach(session.workspaceDirectory.groups) { group in
                    Section(projectTitle(group.project)) {
                        ForEach(group.workspaces) { workspace in
                            Button {
                                Haptics.selection()
                                draft.move(toWorkspace: workspace.id, cwd: workspace.cwd)
                            } label: {
                                Text(title(of: workspace))
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("in \(workspaceTitle)")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(.rect)
            }
            .accessibilityLabel("Workspace, \(workspaceTitle)")
            .accessibilityIdentifier("draft.workspaceLine")
            .padding(.bottom, 4)
        }
    }

    private var workspaceTitle: String {
        guard let workspaceId = draft.workspaceId,
            let workspace = session.workspaceDirectory.workspace(id: workspaceId)
        else { return "New session" }
        return title(of: workspace)
    }

    private func title(of workspace: WorkspaceDescriptor) -> String {
        if let title = workspace.title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return title
        }
        return workspace.branch ?? workspace.name
    }

    private func projectTitle(_ project: WorkspaceProjectDescriptor) -> String {
        let custom = project.projectCustomName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom, !custom.isEmpty { return custom }
        return project.projectDisplayName
    }

    // MARK: Composer

    /// §4.1: a one-line pill at rest, the two-row card once focused or holding text, an
    /// attachment or an error.
    private var composerExpanded: Bool {
        focused || !trimmedText.isEmpty || !tray.isEmpty || errorText != nil
    }

    /// No workspaces at all: nothing can be created yet, so the hero asks for a project instead
    /// of offering a composer (§3.1).
    private var needsProject: Bool {
        session.workspaceDirectory.hasLoaded && session.workspaceDirectory.workspaces.isEmpty
    }

    private var trimmedText: String {
        draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var errorText: String? {
        attachmentError ?? draft.error
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            composerCard
        }
        .padding(.horizontal, composerExpanded ? 8 : 16)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: composerExpanded)
        .padding(.bottom, 8)
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: composerExpanded ? 8 : 0) {
            if composerExpanded { attachmentTray }
            if composerExpanded { dictationDeniedNote }
            if composerExpanded, let message = errorText { errorNote(message) }
            fieldRow
            if composerExpanded { controlRow }
        }
        .composerCardChrome(expanded: composerExpanded)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: composerExpanded)
    }

    /// The add button overlays the field's leading edge at rest instead of being its sibling, so
    /// the field keeps one structural position and the keyboard holds when the pill grows.
    private var fieldRow: some View {
        HStack(spacing: 8) {
            textField
                .padding(.leading, composerExpanded ? 0 : 44)
                .overlay(alignment: .leading) {
                    if !composerExpanded { addMenu }
                }
            if !composerExpanded { micButton }
        }
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            addMenu
            ComposerModelChip(
                modelLabel: modelLabel,
                thinkingLabel: thinkingLabel,
                providerLabel: draft.providerId == nil ? nil : providerLabel
            ) {
                focused = false
                showControls = true
            }
            Spacer(minLength: 0)
            micButton
            sendButton
        }
    }

    private var textField: some View {
        TextField(
            "", text: $draft.text,
            // Upstream `composer.placeholders.mobile` (en.ts:117).
            prompt: Text("Message, @files, /commands")
                .foregroundStyle(ClaudePalette.secondaryInk),
            axis: .vertical
        )
        .font(typography.sans(18))
        .lineLimit(composerExpanded ? 1...12 : 1...1)
        .fixedSize(horizontal: false, vertical: true)
        .focused($focused)
        .tint(ClaudePalette.orange)
        .padding(.horizontal, composerExpanded ? 6 : 2)
        .padding(.top, composerExpanded ? 7 : 0)
        .accessibilityIdentifier("draft.draft")
    }

    private var addMenu: some View {
        Menu {
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 10, matching: .images) {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera", systemImage: "camera") { showCameraPicker = true }
            }
            Button("Files", systemImage: "folder") { showFileImporter = true }
            if UIPasteboard.general.hasImages {
                Button("Paste image", systemImage: "doc.on.clipboard") { pasteImage() }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .regular))
                .frame(width: 36, height: 36)
                .foregroundStyle(ClaudePalette.ink)
                .background(ClaudePalette.chip, in: .circle)
        }
        .accessibilityLabel("Add attachment")
    }

    private var micButton: some View {
        ComposerMicButton(isListening: dictation.isListening, level: Double(dictation.level)) {
            if dictation.isListening {
                dictation.stop(keepingDraft: true)
            } else {
                dictation.toggle(currentDraft: draft.text)
            }
        }
    }

    @ViewBuilder private var sendButton: some View {
        if draft.isCreating {
            ProgressView()
                .controlSize(.small)
                .frame(width: 36, height: 36)
                .accessibilityLabel("Creating…")
        } else {
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.white)
                    .background(ClaudePalette.orange, in: .circle)
                    .opacity(canSend ? 1 : 0.4)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send message")
            .accessibilityIdentifier("draft.send")
        }
    }

    private func errorNote(_ text: String) -> some View {
        Text(text)
            .font(typography.sans(13))
            .foregroundStyle(ClaudePalette.failureInk)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var dictationDeniedNote: some View {
        if dictation.isDenied {
            HStack(spacing: 8) {
                Image(systemName: "mic.slash")
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.failureInk)
                Text("Dictation is off. Enable Microphone and Speech Recognition in Settings.")
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(typography.sans(12, weight: .semibold))
                .foregroundStyle(ClaudePalette.orange)
                .accessibilityLabel("Open Settings")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private var modelLabel: String {
        guard let modelId = draft.modelId else { return "Model" }
        return session.agentControl.models(forProvider: draft.providerId ?? "")
            .first(where: { $0.id == modelId })?.label ?? modelId
    }

    private var providerLabel: String {
        guard let providerId = draft.providerId else { return "" }
        return session.agentControl.provider(providerId)?.label ?? providerId
    }

    private var thinkingLabel: String? {
        guard let thinkingId = draft.thinkingOptionId, let modelId = draft.modelId else {
            return nil
        }
        return session.agentControl.thinkingOptions(
            forProvider: draft.providerId ?? "", modelId: modelId
        ).first(where: { $0.id == thinkingId })?.label
    }

    // MARK: Sending

    private var hasUploadingAttachment: Bool {
        tray.contains { item in
            switch item.phase {
            case .pending, .uploading: true
            case .done, .attached, .failed: false
            }
        }
    }

    private var readyAttachments: [AgentAttachment] {
        tray.compactMap { item -> AgentAttachment? in
            switch item.phase {
            case .done(let file): .uploadedFile(file)
            case .attached(let attachment): attachment
            case .pending, .uploading, .failed: nil
            }
        }
    }

    private var canSend: Bool {
        guard !draft.isCreating, !hasUploadingAttachment else { return false }
        return draft.canSend(hasAttachments: !readyAttachments.isEmpty)
    }

    private func send() {
        guard canSend else { return }
        dictation.stop(keepingDraft: true)
        attachmentError = nil
        focused = false
        Haptics.send()
        let attachments = readyAttachments
        Task {
            guard
                let agentId = await draft.create(
                    using: session.agentControl, attachments: attachments)
            else { return }
            tray = []
            await session.refreshAgents()
            onCreated(agentId)
        }
    }

    // MARK: Catalogue

    private func loadCatalogue() async {
        let catalog = session.agentControl
        let needsLoad: Bool
        switch catalog.phase {
        case .idle, .failed: needsLoad = true
        case .loading, .ready: needsLoad = catalog.providers.isEmpty
        }
        if needsLoad {
            await catalog.loadCatalog(cwd: draft.cwd.isEmpty ? nil : draft.cwd)
        }
        seedIfNeeded()
    }

    /// Seeds once the catalogue can answer, and again if the chosen provider disappears from it
    /// or arrives without models (a provider that was still probing). A user's picks are never
    /// overwritten otherwise.
    private func seedIfNeeded() {
        let catalog = session.agentControl
        guard let providerId = draft.providerId, catalog.provider(providerId) != nil else {
            draft.seed(catalog: catalog)
            return
        }
        if draft.modelId == nil, catalog.defaultModel(forProvider: providerId) != nil {
            draft.seed(catalog: catalog)
        }
    }

    // MARK: Attachments

    private var attachmentTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(tray) { item in
                    ComposerAttachmentPill(
                        item: item,
                        uploadProgress: session.fileUploader.progress,
                        onRemove: { tray.removeAll { $0.id == item.id } },
                        onRetry: {
                            retry(item.id)
                        },
                        onTapImage: { image in viewerImage = image })
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
    }

    private func attachImageData(_ data: Data, fileName: String) {
        guard let processed = ComposerImageProcessor.downscaledJPEG(data: data) else {
            attachmentError = "Couldn't read that image."
            return
        }
        add(
            ComposerAttachmentItem(
                fileName: fileName, mimeType: "image/jpeg", byteCount: processed.data.count,
                data: processed.data, thumbnail: processed.image))
    }

    private func handlePickedPhotos(_ selection: [PhotosPickerItem]) {
        Task {
            for picked in selection {
                guard let data = try? await picked.loadTransferable(type: Data.self) else {
                    continue
                }
                attachImageData(data, fileName: "photo-\(UUID().uuidString.prefix(8)).jpg")
            }
            photoSelection = []
        }
    }

    private func attachFileURLs(_ urls: [URL]) {
        for url in urls {
            let name = url.lastPathComponent
            guard url.startAccessingSecurityScopedResource() else {
                attachmentError = "Couldn't open \(name)."
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else {
                attachmentError = "Couldn't read \(name)."
                continue
            }
            guard data.count <= ConversationUpload.maxBytes else {
                attachmentError = "\(name) is too large (50 MB max)."
                continue
            }
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            add(
                ComposerAttachmentItem(
                    fileName: name, mimeType: mimeType, byteCount: data.count, data: data,
                    thumbnail: nil))
        }
    }

    private func pasteImage() {
        guard let image = UIPasteboard.general.image,
            let data = image.jpegData(compressionQuality: 1.0)
        else {
            attachmentError = "Failed to paste image"
            return
        }
        attachImageData(data, fileName: "pasted-\(UUID().uuidString.prefix(8)).jpg")
    }

    private func add(_ item: ComposerAttachmentItem) {
        attachmentError = nil
        tray.append(item)
        pumpUploads()
    }

    private func retry(_ itemId: UUID) {
        guard let index = tray.firstIndex(where: { $0.id == itemId }) else { return }
        tray[index].phase = .pending
        pumpUploads()
    }

    /// One upload at a time through the session's shared channel; a draft has no agent yet, so
    /// the files are uploaded before the create request and ride it as `uploadedFile`s.
    private func pumpUploads() {
        guard !uploadPumpRunning else { return }
        uploadPumpRunning = true
        Task {
            defer { uploadPumpRunning = false }
            while let pending = firstPending() {
                markUploading(pending.id)
                let result = await session.fileUploader.upload(
                    data: pending.data, fileName: pending.fileName, mimeType: pending.mimeType)
                guard let index = tray.firstIndex(where: { $0.id == pending.id }) else { continue }
                if let result {
                    tray[index].phase = .done(result)
                } else {
                    tray[index].phase = .failed(
                        session.fileUploader.error ?? "The upload failed.")
                }
            }
        }
    }

    private func firstPending() -> ComposerAttachmentItem? {
        tray.first { item in
            if case .pending = item.phase { true } else { false }
        }
    }

    private func markUploading(_ itemId: UUID) {
        guard let index = tray.firstIndex(where: { $0.id == itemId }) else { return }
        tray[index].phase = .uploading
    }
}
#endif
