#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What the composer is writing into.
enum ComposerMode {
    /// An open agent: the text is `store.draft`, and send goes through the conversation.
    case conversation
    /// A new session, before its agent exists: the text is `draft.text`.
    case draft(DraftSession)
}

/// The one composer (R6 §5): the conversation's two-row card, and the draft's card once it is
/// expanded. Every derived value (`canSend`, `isTall`, `slashQuery`, `mentionQuery`) is computed
/// here, so the rest of the screen never reads the draft.
///
/// **Reads:** the text binding, `store.isRunning`, `store.actionError`, `store.agent` (model,
/// provider, features), `store.contextUsage`, and the controller's slash / mention / queue /
/// attachment / dictation / voice state.
struct ComposerView: View {
    let mode: ComposerMode
    /// The conversation; nil in draft mode.
    let store: ConversationStore?
    /// The open agent's controller; nil in draft mode.
    let controller: ChatController?
    /// Draft mode: the session's stores (catalogue for create, the upload channel, agents).
    let draftHost: HostSession?
    /// Draft mode: the shell swaps its conversation in once the agent exists.
    let onCreated: ((String) -> Void)?

    @Binding var text: String
    @FocusState.Binding var focused: Bool

    /// Draft mode's own tray: there is no agent id to key the shared store by yet, and a draft
    /// uploads through the session's channel before the create request.
    @State private var localTray: [ComposerAttachmentItem] = []
    @State private var uploadPumpRunning = false
    @State private var localAttachmentError: String?
    @State private var draftDictation = DictationController()
    @State private var showDraftControls = false
    @State private var showDraftFullScreen = false

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showCameraPicker = false
    @State private var showFileImporter = false
    @State private var showForgePicker = false
    @State private var attachmentViewerImage: UIImage?
    @State private var surfaceHeight: CGFloat = 0

    @Environment(\.composerFocusRequested) private var composerFocusRequested
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DefaultSendBehavior.storageKey) private var defaultSend = DefaultSendBehavior.steer.rawValue

    init(
        mode: ComposerMode, store: ConversationStore, controller: ChatController,
        focused: FocusState<Bool>.Binding
    ) {
        self.mode = mode
        self.store = store
        self.controller = controller
        self.draftHost = nil
        self.onCreated = nil
        self._text = Binding(
            get: { store.draft }, set: { store.draft = $0 })
        self._focused = focused
    }

    /// The draft screen's composer: the same card, before its agent exists (R6 §5).
    init(
        draft: DraftSession, session: HostSession, onCreated: @escaping (String) -> Void,
        focused: FocusState<Bool>.Binding
    ) {
        self.mode = .draft(draft)
        self.store = nil
        self.controller = nil
        self.draftHost = session
        self.onCreated = onCreated
        self._text = Binding(
            get: { draft.text }, set: { draft.text = $0 })
        self._focused = focused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isDraft {
                slashMenu
                mentionMenu
                queueStack
            }
            composerCard
        }
        .padding(.horizontal, isDraft && !composerExpanded ? 16 : 8)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { height in
            surfaceHeight = height
        }
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: slashQuery != nil)
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: mentionQuery != nil)
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: queueIsEmpty == false)
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: fastModeActive)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            handlePickedPhotos(items)
        }
        .onAppear {
            guard isDraft else { return }
            draftDictation.onDraft = { text = $0 }
        }
        .onDisappear {
            guard isDraft else { return }
            draftDictation.stop(keepingDraft: true)
        }
    }

    // MARK: Derived (all local to the composer)

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Grow-to-cap: an O(1)-ish check, never `components(separatedBy:)`.
    private var isTall: Bool {
        DraftMetrics.isTall(text)
    }

    private var isDraft: Bool {
        if case .draft = mode { return true }
        return false
    }

    private var draftSession: DraftSession? {
        if case .draft(let draft) = mode { return draft }
        return nil
    }

    /// §4.1: the draft's one-line pill at rest becomes the two-row card once focused, holding
    /// text, an attachment, an error or dictation. A live conversation is always the card (V5 §4.4).
    private var composerExpanded: Bool {
        guard isDraft else { return true }
        return focused || !trimmedText.isEmpty || !trayItems.isEmpty || errorText != nil
            || (activeDictation?.isListening ?? false)
    }

    /// The dictation controller that belongs to this composer: the conversation's or a draft's own.
    private var activeDictation: DictationController? {
        controller?.dictation ?? draftDictation
    }

    private var slashQuery: String? {
        controller?.slashQuery(in: text)
    }

    private var mentionQuery: String? {
        ChatMentions.query(in: text)
    }

    private var trayItems: [ComposerAttachmentItem] {
        controller?.trayItems ?? localTray
    }

    private var hasUploadingAttachment: Bool {
        trayItems.contains { item in
            switch item.phase {
            case .decoding, .pending, .uploading: true
            case .done, .attached, .failed: false
            }
        }
    }

    private var readyAttachments: [AgentAttachment] {
        trayItems.compactMap { item -> AgentAttachment? in
            switch item.phase {
            case .done(let attachment): .uploadedFile(attachment)
            case .attached(let attachment): attachment
            case .decoding, .pending, .uploading, .failed: nil
            }
        }
    }

    /// Send is enabled with an empty draft when there's a finished attachment; disabled while an
    /// upload is in flight.
    private var canSend: Bool {
        guard !hasUploadingAttachment else { return false }
        if let draft = draftSession {
            return draft.canSend(hasAttachments: !readyAttachments.isEmpty)
        }
        if !trimmedText.isEmpty { return true }
        return !readyAttachments.isEmpty
    }

    /// What the card shows under the field when something went wrong.
    private var errorText: String? {
        if let store { return store.actionError }
        return localAttachmentError ?? draftSession?.error
    }

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    private var composerFieldLineLimit: Int {
        ComposerFieldLimit.lines(availableHeight: surfaceHeight)
    }

    private var modelChipTitle: String {
        modelLabel ?? "Model"
    }

    private var modelLabel: String? {
        if let draft = draftSession {
            guard let catalog = draftHost?.agentControl, let modelId = draft.modelId else {
                return nil
            }
            return catalog.models(forProvider: draft.providerId ?? "")
                .first(where: { $0.id == modelId })?.label ?? modelId
        }
        guard let store, let agent = store.agent else { return nil }
        let catalog = controller?.session.agentControl
        if let id = agent.model,
            let match = catalog?.models(forProvider: agent.provider).first(where: { $0.id == id })
        {
            return match.label
        }
        return catalog?.defaultModel(forProvider: agent.provider)?.label ?? agent.model
    }

    private var thinkingLabel: String? {
        if let draft = draftSession, let thinkingId = draft.thinkingOptionId,
            let modelId = draft.modelId
        {
            return draftHost?.agentControl
                .thinkingOptions(forProvider: draft.providerId ?? "", modelId: modelId)
                .first(where: { $0.id == thinkingId })?.label
        }
        guard let store, let agent = store.agent,
            let model = agent.effectiveThinkingOptionId ?? agent.thinkingOptionId,
            let modelId = agent.model
        else { return nil }
        return controller?.session.agentControl
            .thinkingOptions(forProvider: agent.provider, modelId: modelId)
            .first(where: { $0.id == model })?.label
    }

    /// The provider's fast-mode toggle, matched by the upstream id `"fast_mode"`
    /// (`packages/app/src/agent-controls/policy.ts:4`).
    private var fastModeFeature: AgentFeature.Toggle? {
        guard let features = store?.agent?.features else { return nil }
        for feature in features {
            if case .toggle(let toggle) = feature, toggle.id == "fast_mode" {
                return toggle
            }
        }
        return nil
    }

    private var fastModeActive: Bool { fastModeFeature?.value == true }

    /// The workspace's forge, from the checkout's PR status. Unknown reads as GitHub.
    private var forgeId: String {
        // Read-only: never create a checkout store from a view's body.
        guard let store, let workspaceId = store.agent?.workspaceId,
            let checkout = controller?.session.existingCheckout(workspaceId)
        else { return "github" }
        let forge = checkout.prStatus?.forge?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return forge.isEmpty ? "github" : forge
    }

    private var forgeIsGitLab: Bool { forgeId.lowercased() == "gitlab" }

    private var voice: VoiceModeSession? { controller?.session.voiceSession }
    private var voiceActiveForAgent: Bool {
        guard let controller, let store else { return false }
        return controller.session.voiceSession.isVoiceMode(for: store.agentId)
    }

    private var queueIsEmpty: Bool { controller?.isQueueNonEmpty == true }

    private var defaultSendBehavior: DefaultSendBehavior {
        DefaultSendBehavior(rawValue: defaultSend) ?? .steer
    }

    // MARK: Card

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: composerExpanded ? 8 : 0) {
            if let dictation = activeDictation, dictation.isListening {
                dictationOverlay(dictation)
            } else {
                if composerExpanded { attachmentTray }
                if composerExpanded { dictationDeniedBanner }
                if composerExpanded, let error = errorText {
                    Text(error)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                        .padding(.horizontal, 8)
                        .transition(.opacity)
                }
                fieldRow
                if composerExpanded, voiceActiveForAgent || voice?.phase == .starting {
                    voiceBar
                }
                if composerExpanded { composerControlRow }
            }
        }
        .composerCardChrome(expanded: composerExpanded)
        .animation(Motion.disclosure.resolved(reduceMotion: reduceMotion), value: composerExpanded)
        .onChange(of: composerFocusRequested.wrappedValue) { _, requested in
            guard requested else { return }
            focused = true
            composerFocusRequested.wrappedValue = false
        }
        .onChange(of: controller?.dismissKeyboardRequest) { _, _ in
            focused = false
        }
        // M8b: expand control for tall drafts, left of the crab's spot.
        .overlay(alignment: .topTrailing) { expandComposerButton }
        // The crab stands on the card's top edge, flush with its trailing edge.
        .overlay(alignment: .topTrailing) { mascotCrab }
        .sheet(isPresented: $showDraftControls) {
            if let draft = draftSession, let session = draftHost {
                DraftControlsSheet(session: session, draft: draft)
            }
        }
        .fullScreenCover(isPresented: fullScreenComposerBinding) {
            FullScreenComposer(
                draft: $text,
                isRunning: store?.isRunning ?? false
            ) { send() }
        }
        .modifier(ComposerSheets(
            controller: controller,
            store: store,
            showFileImporter: $showFileImporter,
            showForgePicker: $showForgePicker,
            showCameraPicker: $showCameraPicker,
            attachmentViewerImage: $attachmentViewerImage,
            forgeIsGitLab: forgeIsGitLab,
            onFileURLs: attachFileURLs,
            onCameraImage: { data in
                attachImage(data, fileName: "photo-\(UUID().uuidString.prefix(8)).jpg")
            },
            onForgePick: { item in
                toggleForgeAttachment(item)
                showForgePicker = false
            }))
        .modifier(ComposerVoiceWiring(controller: controller))
        // M17: drop a file row (Files tree / Changes list) onto the composer to attach it as a
        // workspace-file mention.
        .dropDestination(for: String.self) { items, _ in
            guard let path = items.first else { return false }
            insertFileMention(path)
            return true
        }
    }

    private var fullScreenComposerBinding: Binding<Bool> {
        Binding(
            get: { controller?.showFullScreenComposer ?? showDraftFullScreen },
            set: { value in
                if controller != nil {
                    controller?.showFullScreenComposer = value
                } else {
                    showDraftFullScreen = value
                }
            })
    }

    /// The draft overlays its add button on the field's leading edge at rest, so the field keeps
    /// one structural position and the keyboard holds when the pill grows (§4.1).
    @ViewBuilder private var fieldRow: some View {
        if isDraft {
            HStack(spacing: 8) {
                composerTextField
                    .padding(.leading, composerExpanded ? 0 : 44)
                    .overlay(alignment: .leading) {
                        if !composerExpanded { composerAddMenu }
                    }
                if !composerExpanded { dictateButton }
            }
        } else {
            composerTextField
        }
    }

    private var composerTextField: some View {
        TextField(
            "", text: $text,
            prompt: Text(placeholder)
                .foregroundStyle(Palette.secondaryInk),
            axis: .vertical
        )
        .font(.paseo(.body))
        // V5 §3: grow to the cap, then scroll inside the field — the controls row below always
        // stays above the keyboard.
        .lineLimit(1...composerFieldLineLimit)
        .fixedSize(horizontal: false, vertical: true)
        .focused($focused)
        // Audit C: the cursor is ink, not orange.
        .tint(Palette.ink)
        .padding(.horizontal, 6)
        .padding(.top, 7)
        .accessibilityIdentifier("composer.draft")
    }

    /// One string in both modes, from upstream `composer.placeholders.mobile` (en.ts:117).
    private var placeholder: String {
        controller?.composerPrompt ?? "Message, @files, /commands"
    }

    @ViewBuilder private var dictationDeniedBanner: some View {
        if activeDictation?.isDenied == true {
            InlineBanner(
                .failure, title: "Dictation is off.",
                message: "Enable Microphone and Speech Recognition in Settings.",
                systemImage: "mic.slash",
                action: ("Settings", {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }))
                .accessibilityIdentifier("composer.dictation.settings")
        }
    }

    // MARK: Row 2

    private var composerControlRow: some View {
        HStack(spacing: 8) {
            composerAddMenu
            composerModelChip
            fastModeChip
            Spacer(minLength: 0)
            contextMeter
            voiceModeButton
            dictateButton
            composerSendControl
        }
    }

    private var composerAddMenu: some View {
        Menu {
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 10, matching: .images) {
                Label("Photo library", systemImage: "photo.on.rectangle")
            }
            if cameraAvailable {
                Button("Camera", systemImage: "camera") { showCameraPicker = true }
            }
            Button("Files", systemImage: "folder") { showFileImporter = true }
            // iOS has no paste command for views; offer the clipboard image explicitly.
            if UIPasteboard.general.hasImages {
                Button("Paste image", systemImage: "doc.on.clipboard") { pasteImageFromClipboard() }
            }
            Button(
                forgeIsGitLab ? "Add issue or MR" : "Add issue or PR",
                systemImage: "arrow.triangle.branch"
            ) {
                openForgePicker()
            }
            Button("Mention a file", systemImage: "at") { mentionFile() }
            Divider()
            Button("New agent", systemImage: "plus.bubble") {
                controller?.newAgent(draft: text)
            }
            Button("Copy agent ID", systemImage: "doc.on.doc") {
                controller?.copyAgentId()
            }
        } label: {
            Image(systemName: "plus")
                .font(.glyph(.regular, weight: .regular))
                .frame(width: 36, height: 36)
                .foregroundStyle(Palette.ink)
                .background(Palette.chip, in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Add to agent")
    }

    private var composerModelChip: some View {
        ComposerModelChip(
            modelLabel: modelChipTitle,
            thinkingLabel: thinkingLabel,
            providerLabel: draftSession?.providerId == nil ? nil : draftProviderLabel,
            providerIconSvg: draftSession?.providerId == nil ? nil : draftProviderIconSvg
        ) {
            focused = false
            if controller != nil {
                controller?.sheet = .controls
            } else {
                showDraftControls = true
            }
        }
    }

    /// Draft only: the provider's label and brand mark in the model chip (§3.1).
    private var draftProviderLabel: String? {
        guard let providerId = draftSession?.providerId, let catalog = draftHost?.agentControl
        else { return nil }
        return catalog.provider(providerId)?.label ?? providerId
    }

    private var draftProviderIconSvg: String? {
        guard let providerId = draftSession?.providerId, let catalog = draftHost?.agentControl
        else { return nil }
        return catalog.provider(providerId)?.iconSvg
    }

    @ViewBuilder private var fastModeChip: some View {
        if fastModeActive {
            Button {
                Haptics.selection()
                Task { await store?.setFeatureToggle(featureId: "fast_mode", value: false) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.glyph(.small, weight: .semibold))
                    Text("Fast")
                        .font(.paseo(.footnote, weight: .semibold))
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Palette.chip, in: .capsule)
            }
            .accessibilityLabel("Fast mode on; turn off")
            .accessibilityIdentifier("composer.fastmode")
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    @ViewBuilder private var contextMeter: some View {
        if let usage = store?.contextUsage, let percent = usage.percentUsed,
            usage.usedTokens != nil, usage.maxTokens != nil
        {
            Button {
                Haptics.selection()
                controller?.showContextSheet = true
            } label: {
                ClaudeMeterRing(percent: percent, size: 16, lineWidth: 1.5)
                    .frame(width: 36, height: 36)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Context window, \(Int(percent.rounded())) percent used")
            .accessibilityIdentifier("composer.contextMeter")
        }
    }

    @ViewBuilder private var voiceModeButton: some View {
        if let voice, voice.isVoiceAvailable {
            Button {
                toggleVoiceMode()
            } label: {
                Image(
                    systemName: voiceActiveForAgent && voice.isMuted
                        ? "mic.slash.fill" : "waveform.and.mic"
                )
                .font(.glyph(.regular, weight: .medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(voiceActiveForAgent ? .white : Palette.ink)
                .background(voiceActiveForAgent ? Palette.orange : Palette.chip, in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
            }
            .accessibilityLabel(
                voiceActiveForAgent
                    ? (voice.isMuted ? "Unmute voice mode" : "Mute Voice mode")
                    : "Enable Voice mode")
            .accessibilityIdentifier("composer.voiceMode")
            .disabled(voice.isVoiceSwitching)
        }
    }

    private var dictateButton: some View {
        let dictation = activeDictation
        return ComposerMicButton(
            isListening: dictation?.isListening ?? false,
            level: Double(dictation?.level ?? 0)
        ) {
            guard let dictation else { return }
            if dictation.isListening {
                dictation.stop(keepingDraft: true)
            } else {
                dictation.toggle(currentDraft: text)
            }
        }
    }

    private func dictationOverlay(_ dictation: DictationController) -> some View {
        DictationOverlay(
            level: Double(dictation.level),
            duration: dictation.duration,
            onCancel: { dictation.cancel() },
            onAccept: { dictation.stop(keepingDraft: true) },
            onAcceptAndSend: {
                dictation.stop(keepingDraft: true)
                send()
            })
    }

    @ViewBuilder private var voiceBar: some View {
        if let voice, let controller {
            VoiceBar(voice: voice, engine: controller.voiceEngine)
        }
    }

    @ViewBuilder private var composerSendControl: some View {
        if store?.isRunning == true && trimmedText.isEmpty {
            Button {
                Task { await store?.cancel() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.glyph(.regular, weight: .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Palette.background)
                    .background(Palette.ink, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop response")
            .accessibilityIdentifier("composer.stop")
        } else {
            QueueSendButton(
                isRunning: store?.isRunning ?? false, canSend: canSend
            ) {
                tapSend()
            } onQueue: {
                longPressSend()
            }
            // ⌘↩ sends, whatever tap would have done.
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("composer.send")
        }
    }

    // MARK: Sending

    private func tapSend() {
        if defaultSendBehavior == .queue, store?.isRunning == true {
            queueDraft()
            return
        }
        let behavior: String? =
            store?.isRunning == true && defaultSendBehavior == .interrupt ? "interrupt" : nil
        send(behavior: behavior)
    }

    /// Long-press on the send button: the opposite of the default between steer and queue
    /// (interrupt has no opposite there, so it queues).
    private func longPressSend() {
        switch defaultSendBehavior {
        case .steer, .interrupt: queueDraft()
        case .queue: send()
        }
    }

    private func send(behavior: String? = nil) {
        focused = false
        if let draft = draftSession, let session = draftHost {
            guard canSend else { return }
            draftDictation.stop(keepingDraft: true)
            localAttachmentError = nil
            draft.clearError()
            Haptics.send()
            let attachments = readyAttachments
            Task {
                guard
                    let agentId = await draft.create(
                        using: session.agentControl, attachments: attachments)
                else { return }
                localTray = []
                await session.refreshAgents()
                onCreated?(agentId)
            }
            return
        }
        controller?.dictation.stop(keepingDraft: true)
        controller?.send(behavior: behavior, attachments: readyAttachments)
    }

    private func queueDraft() {
        controller?.queueDraft(attachments: trayItems)
        guard controller?.isQueueNonEmpty == true else { return }
        text = ""
    }

    // MARK: Attachments

    @ViewBuilder private var attachmentTray: some View {
        if !trayItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(trayItems) { item in
                        ComposerAttachmentPill(
                            item: item,
                            uploadProgress: uploadProgress,
                            onRemove: { removeAttachment(item.id) },
                            onRetry: { retryAttachment(item.id) },
                            onTapImage: { image in attachmentViewerImage = image })
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 1)
            }
        }
    }

    private var uploadProgress: Double {
        if let store { return store.uploads.progress }
        return draftHost?.fileUploader.progress ?? 0
    }

    private func attachFileURLs(_ urls: [URL]) {
        if let controller {
            controller.attachFileURLs(urls)
            return
        }
        for url in urls {
            let name = url.lastPathComponent
            guard url.startAccessingSecurityScopedResource() else {
                localAttachmentError = "Couldn't open \(name)."
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else {
                localAttachmentError = "Couldn't read \(name)."
                continue
            }
            guard data.count <= ConversationUpload.maxBytes else {
                localAttachmentError = "\(name) is too large (50 MB max)."
                continue
            }
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            localTray.append(
                ComposerAttachmentItem(
                    fileName: name, mimeType: mimeType, byteCount: data.count, data: data,
                    thumbnail: nil))
        }
        pumpLocalUploads()
    }

    private func handlePickedPhotos(_ selection: [PhotosPickerItem]) {
        Task {
            for picked in selection {
                guard let data = try? await picked.loadTransferable(type: Data.self) else {
                    continue
                }
                attachImage(data, fileName: "photo-\(UUID().uuidString.prefix(8)).jpg")
            }
            photoSelection = []
        }
    }

    /// A picked or pasted image: the conversation hands it to its controller (which decodes off
    /// main into the shared tray); a draft shows the `.decoding` tile and does the same here.
    private func attachImage(_ data: Data, fileName: String) {
        if let controller {
            controller.attachImageData(data, fileName: fileName)
            return
        }
        let item = ComposerAttachmentItem(
            fileName: fileName, mimeType: "image/jpeg", byteCount: data.count, data: Data(),
            thumbnail: nil, phase: .decoding)
        localTray.append(item)
        Task {
            let processed = await Task.detached(priority: .userInitiated) {
                ComposerImageProcessor.downscaledJPEG(data: data)
            }.value
            guard let index = localTray.firstIndex(where: { $0.id == item.id }) else { return }
            guard let processed else {
                localTray[index].phase = .failed("Couldn't read that image.")
                return
            }
            localTray[index].data = processed.data
            localTray[index].thumbnail = processed.image
            localTray[index].byteCount = processed.data.count
            localTray[index].phase = .pending
            pumpLocalUploads()
        }
    }

    /// Draft only: one upload at a time through the session's shared channel; the files ride the
    /// create request as `uploadedFile`s.
    private func pumpLocalUploads() {
        guard let session = draftHost, !uploadPumpRunning else { return }
        uploadPumpRunning = true
        Task {
            defer { uploadPumpRunning = false }
            while let pending = localTray.first(where: { item in
                if case .pending = item.phase { true } else { false }
            }) {
                markLocal(pending.id, .uploading)
                let result = await session.fileUploader.upload(
                    data: pending.data, fileName: pending.fileName, mimeType: pending.mimeType)
                guard let index = localTray.firstIndex(where: { $0.id == pending.id }) else {
                    continue
                }
                if let result {
                    localTray[index].phase = .done(result)
                } else {
                    localTray[index].phase = .failed(
                        session.fileUploader.error ?? "The upload failed.")
                }
            }
        }
    }

    private func markLocal(_ id: UUID, _ phase: ComposerAttachmentPhase) {
        guard let index = localTray.firstIndex(where: { $0.id == id }) else { return }
        localTray[index].phase = phase
    }

    private func removeAttachment(_ id: UUID) {
        if let controller {
            controller.removeAttachment(id)
            return
        }
        localTray.removeAll { $0.id == id }
    }

    private func retryAttachment(_ id: UUID) {
        if let controller {
            controller.retryAttachment(id)
            return
        }
        markLocal(id, .pending)
        pumpLocalUploads()
    }

    private func pasteImageFromClipboard() {
        if let controller {
            controller.pasteImageFromClipboard()
            return
        }
        guard let image = UIPasteboard.general.image,
            let data = image.jpegData(compressionQuality: 1.0)
        else {
            localAttachmentError = "Failed to paste image"
            return
        }
        attachImage(data, fileName: "pasted-\(UUID().uuidString.prefix(8)).jpg")
    }

    private func mentionFile() {
        if text.isEmpty {
            text = "@"
        } else if text.hasSuffix(" ") || text.hasSuffix("\n") {
            text += "@"
        } else {
            text += " @"
        }
        focused = true
    }

    /// Dropped-file drag (M17): inserts `@relative/path ` like "Add to chat" does.
    private func insertFileMention(_ relPath: String) {
        let trimmed = relPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let mention = "@\(trimmed) "
        if text.isEmpty {
            text = mention
        } else if text.hasSuffix(" ") || text.hasSuffix("\n") {
            text += mention
        } else {
            text += " " + mention
        }
        focused = true
    }

    private func openForgePicker() {
        guard let store, let controller else { return }
        if let workspaceId = store.agent?.workspaceId,
            let workspace = controller.session.workspaceDirectory.workspace(id: workspaceId)
        {
            let checkout = controller.session.checkout(for: workspace)
            Task { await checkout.loadPrStatus() }
        }
        showForgePicker = true
    }

    /// The forge items already in the tray, by picker row id (kind:number).
    private var selectedForgeIds: [String] {
        trayItems.compactMap { item in
            guard case .attached(let attachment) = item.phase else { return nil }
            return switch attachment {
            case .forgeChangeRequest(let forge): "change_request:\(forge.number)"
            case .forgeIssue(let forge): "issue:\(forge.number)"
            default: nil
            }
        }
    }

    /// Toggles one picker row into the tray: picking an attached row removes it.
    private func toggleForgeAttachment(_ item: ForgeSearchItem) {
        guard let store, let controller else { return }
        if let existing = trayItems.first(where: { candidate in
            guard case .attached(let attachment) = candidate.phase else { return false }
            return switch (attachment, item.kind) {
            case (.forgeChangeRequest(let forge), .changeRequest): forge.number == item.number
            case (.forgeIssue(let forge), .issue): forge.number == item.number
            default: false
            }
        }) {
            controller.attachmentStore.remove(existing.id, from: store.agentId, store: store)
            return
        }
        guard let attachment = item.asAttachment else { return }
        controller.attachmentStore.addForge(attachment, to: store.agentId, store: store)
    }

    // MARK: Voice

    private func toggleVoiceMode() {
        guard let store, let controller, let voice else { return }
        if voice.isVoiceMode(for: store.agentId) {
            voice.setMuted(!voice.isMuted)
            return
        }
        if store.isRunning {
            controller.showToast("Interrupt the agent before starting voice mode")
            return
        }
        Haptics.selection()
        Task {
            let ok = await voice.start(agentId: store.agentId)
            if !ok {
                if voice.missingModelIds.isEmpty {
                    controller.showToast(voice.error ?? "Voice mode is not available.")
                } else {
                    controller.showToast(
                        "Voice needs models that aren't downloaded. Download them in Settings → Voice.")
                }
            }
        }
    }

    // MARK: Slash and mentions

    @ViewBuilder private var slashMenu: some View {
        if let controller, let query = slashQuery {
            SlashMenu(controller: controller, query: query, onPick: { command in
                text = "/" + command.name + " "
                focused = true
            })
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder private var mentionMenu: some View {
        if let controller, mentionQuery != nil,
            !controller.mentionMatches.isEmpty || controller.mentionIndex.isBuilding
        {
            MentionMenu(
                rows: controller.mentionMatches, isBuilding: controller.mentionIndex.isBuilding
            ) { row in
                controller.handleMentionPick(row)
                focused = true
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: Queue

    @ViewBuilder private var queueStack: some View {
        if let controller, controller.isQueueNonEmpty {
            let queue = controller.composerQueue.queue(for: controller.store.agentId)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(queue.messages.prefix(3)) { message in
                    QueueRow(
                        message: message,
                        onEdit: {
                            if controller.editQueuedMessage(message) { focused = true }
                        },
                        onSendNow: { controller.sendQueuedNow(message) })
                }
                if queue.count > 3 {
                    Text("+\(PaseoFormat.integer(queue.count - 3)) more")
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(minHeight: 24)
                        .padding(.leading, 27)
                        .accessibilityLabel("\(queue.count - 3) more queued messages")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: Expand and mascot

    @ViewBuilder private var expandComposerButton: some View {
        if isTall {
            Button {
                Haptics.selection()
                if controller != nil {
                    controller?.showFullScreenComposer = true
                } else {
                    showDraftFullScreen = true
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 28, height: 28)
                    .background(Palette.chip, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .padding(.trailing, 104)
            .padding(.top, 1)
            .accessibilityLabel("Expand composer")
            .transition(.opacity)
        }
    }

    @ViewBuilder private var mascotCrab: some View {
        if let controller, mascotEnabled {
            MascotCrab(controller: controller, store: store)
        }
    }

    @AppStorage(PaseoSettingsKeys.mascot) private var mascotEnabled = true
}

// MARK: - Extracted pieces

/// The slash-command menu body.
struct SlashMenu: View {
    let controller: ChatController
    let query: String
    let onPick: (AgentSlashCommand) -> Void

    var body: some View {
        ComposerMenuContainer(accessibilityIdentifier: "composer.slashMenu") {
            Group {
                switch controller.slashState {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading commands…")
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .ready:
                    readyRows
                case .idle:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder private var readyRows: some View {
        let commands = controller.filteredSlashCommands(for: query)
        if let error = controller.slashError, controller.slashCommands.isEmpty {
            Text(error)
                .font(.paseo(.caption))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if commands.isEmpty {
            if !controller.slashCommands.isEmpty {
                Text("No matching commands")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(commands) { command in
                        Button {
                            Haptics.selection()
                            onPick(command)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text("/" + command.name)
                                        .font(.paseo(.code, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    if !command.argumentHint.isEmpty {
                                        Text(command.argumentHint)
                                            .font(.paseo(.codeCaption))
                                            .foregroundStyle(Palette.tertiaryInk)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if command.kind == .skill {
                                        Image(systemName: "sparkles")
                                            .font(.glyph(.small, weight: .medium))
                                            .foregroundStyle(Palette.secondaryInk)
                                            .accessibilityLabel("Skill")
                                    }
                                }
                                if !command.description.isEmpty {
                                    Text(command.description)
                                        .font(.paseo(.caption))
                                        .foregroundStyle(Palette.secondaryInk)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 46)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            ["/\(command.name)", command.description]
                                .filter { !$0.isEmpty }
                                .joined(separator: ", "))
                    }
                }
            }
            .frame(maxHeight: 276)
            .scrollIndicators(.hidden)
        }
    }
}

/// One queued message.
struct QueueRow: View {
    let message: MessageQueue.QueuedMessage
    let onEdit: () -> Void
    let onSendNow: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)
            Text(message.text)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button {
                Haptics.selection()
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 36, height: 36)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit queued message")
            Button {
                Haptics.selection()
                onSendNow()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 36, height: 36)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send queued message now")
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 10)
        .contentShape(.rect)
    }
}

/// The live voice row: mute toggle, volume meter, stop/interrupt (upstream wording).
struct VoiceBar: View {
    let voice: VoiceModeSession
    let engine: VoiceAudioEngine

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.selection()
                voice.setMuted(!voice.isMuted)
            } label: {
                Image(systemName: voice.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.glyph(.regular, weight: .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.white)
                    .background(voice.isMuted ? Palette.failureInk : Palette.chip, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel(voice.isMuted ? "Unmute voice" : "Mute voice")
            .accessibilityIdentifier("composer.voice.mute")

            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    let height = [8.0, 13.0, 18.0, 13.0, 8.0][index]
                    Capsule()
                        .fill(Palette.ink.opacity(0.85))
                        .frame(width: 4, height: height * CGFloat(max(0.15, voice.volume) + 0.05))
                        .scaleEffect(y: voice.isMuted ? 0.3 : 1, anchor: .center)
                }
            }
            .frame(width: 52, height: 20)
            .accessibilityLabel("Voice volume, \(Int((voice.volume * 100).rounded())) percent")
            .accessibilityIdentifier("composer.voice.volume")

            Spacer(minLength: 0)

            Button {
                Haptics.selection()
                Task { await voice.stop() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.glyph(.regular, weight: .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.white)
                    .background(Palette.failureInk, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Stop realtime voice and interrupt turn")
            .accessibilityIdentifier("composer.voice.stop")
            .disabled(voice.phase == .stopping)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Shared composer pieces

/// V5 §3: a long draft must never push the composer's controls under the keyboard. The field grows
/// to this many lines and then scrolls inside itself — `TextField(axis: .vertical)` scrolls once it
/// reaches its line limit.
enum ComposerFieldLimit {
    /// About 40 % of the space above the keyboard, in text lines of the 17 pt composer face
    /// (≈ 8 lines on an iPhone in portrait). Clamped so an unmeasured pass still leaves a usable
    /// field, and a tall screen can never take more than a third of the card.
    static func lines(
        availableHeight: CGFloat, fontSize: CGFloat = Typography.chatBodySize
    ) -> Int {
        guard availableHeight > 0 else { return 9 }
        let lineHeight = fontSize * 1.4
        return min(10, max(3, Int((availableHeight * 0.4) / lineHeight)))
    }
}

/// The composer's card: a one-line pill at rest, a lifted card once open (UX-SPEC §4.1). Shared
/// by the live conversation and the draft so both grow the same way. The live conversation always
/// passes `expanded: true` (V5 §4.4); only the draft still collapses to the pill.
struct ComposerCardChrome: ViewModifier {
    let expanded: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, expanded ? 8 : 12)
            .padding(.vertical, expanded ? 8 : 0)
            .frame(minHeight: 48)
            .background(
                Palette.composer,
                in: .rect(cornerRadius: Radius.group, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
                    .stroke(Palette.composerBorder, lineWidth: 0.7)
            }
    }
}

extension View {
    func composerCardChrome(expanded: Bool) -> some View {
        modifier(ComposerCardChrome(expanded: expanded))
    }
}

/// "Model *Thinking*" in one grey chip (§4.1b). A draft passes its provider's label, because the
/// provider is still a choice there (§3.1); a live agent has one already and shows the model only.
/// No accent in any state (§0.1).
struct ComposerModelChip: View {
    var modelLabel: String
    var thinkingLabel: String?
    /// Draft only: draws the provider's glyph in front of the model.
    var providerLabel: String?
    /// Draft only: the provider's `iconSvg`, so the glyph is the real mark.
    var providerIconSvg: String?
    var action: () -> Void


    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let providerLabel {
                    ProviderGlyph(label: providerLabel, iconSvg: providerIconSvg)
                }
                Text(modelLabel)
                if let thinkingLabel {
                    Text(thinkingLabel).foregroundStyle(Palette.secondaryInk)
                }
            }
            .font(.paseo(.callout))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Palette.chip, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model, thinking and mode")
        .accessibilityIdentifier("composer.model")
    }
}

/// The provider's mark in the model chip's leading edge. The host catalogue carries per-provider
/// brand SVGs (`ProviderSnapshotEntry.iconSvg`); `ProviderIcon` parses the ones this renderer
/// understands and the shape fills them in ink (§0.1). Anything unparseable — a stroke-only icon,
/// an arc, a `text` glyph — keeps the two-letter monogram, so the chip never shows a hole and
/// still reads the same for every provider.
struct ProviderGlyph: View {
    let label: String
    /// The provider's `iconSvg`, when the catalogue entry carries one.
    var iconSvg: String?

    private let icon: ProviderIcon?

    init(label: String, iconSvg: String? = nil) {
        self.label = label
        self.iconSvg = iconSvg
        self.icon = iconSvg.flatMap(ProviderIcon.parse)
    }

    var body: some View {
        if let icon {
            ProviderIconShape(icon: icon)
                .fill(Palette.secondaryInk)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        } else {
            monogramTile
        }
    }

    private var monogramTile: some View {
        Text(monogram)
            .font(.paseo(.caption2, weight: .semibold))
            .foregroundStyle(Palette.secondaryInk)
            .frame(width: 16, height: 16)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.xs, style: .continuous))
            .accessibilityHidden(true)
    }

    /// "Claude" → "Cl", "openai/codex" → "Co".
    private var monogram: String {
        let letters = label.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop { !$0.isLetter }
        guard let first = letters.first else { return "?" }
        return String(first).uppercased() + String(letters.dropFirst().prefix(1)).lowercased()
    }
}

/// The dictation mic: ink on `chip`, and a filled ink circle while it listens (no accent on a
/// control, §0.1). The draft and the live conversation draw the same control.
struct ComposerMicButton: View {
    let isListening: Bool
    /// 0…1 input level while listening.
    let level: Double
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: isListening ? "mic.fill" : "mic")
                .font(.glyph(.regular, weight: .medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(isListening ? Palette.background : Palette.ink)
                .background(isListening ? Palette.ink : Palette.chip, in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .scaleEffect(scale)
                .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: level)
        }
        .accessibilityLabel(isListening ? "Stop dictation" : "Dictate")
        .accessibilityIdentifier("composer.dictate")
    }

    private var scale: CGFloat {
        guard isListening, !reduceMotion else { return 1 }
        return 1 + CGFloat(level) * 0.18
    }
}

/// Upstream's dictation overlay (`dictation-controls.tsx`, `DictationOverlay`), monochrome: while
/// the mic is live the composer row becomes cancel · input meter · elapsed timer · insert ·
/// insert-and-send. It replaces the field rather than sitting beside it, the way upstream swaps
/// the whole input surface. Wording is en.ts `message.dictation` (:362-371).
struct DictationOverlay: View {
    /// 0…1 input level.
    let level: Double
    /// Seconds since recording started.
    let duration: TimeInterval
    let onCancel: () -> Void
    let onAccept: () -> Void
    let onAcceptAndSend: () -> Void


    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.glyph(.regular, weight: .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Palette.ink)
                    .background(Palette.chip, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel dictation")
            .accessibilityIdentifier("composer.dictation.cancel")

            meter
            Text(formattedDuration)
                .font(.paseo(.callout, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .accessibilityIdentifier("composer.dictation.timer")

            Spacer(minLength: 0)

            actionButton(
                "pencil", label: "Insert transcription",
                identifier: "composer.dictation.insert", action: onAccept)
            actionButton(
                "arrow.up", label: "Insert transcription and send",
                identifier: "composer.dictation.insertAndSend", action: onAcceptAndSend)
        }
        .frame(height: 52)
    }

    /// Ink bars on the card; the same meter the voice bar draws.
    private var meter: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                let height = [8.0, 13.0, 18.0, 13.0, 8.0][index]
                Capsule()
                    .fill(Palette.ink.opacity(0.85))
                    .frame(width: 4, height: height * CGFloat(max(0.15, level) + 0.05))
            }
        }
        .frame(width: 52, height: 20)
        .accessibilityHidden(true)
    }

    private func actionButton(
        _ symbol: String, label: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.glyph(.regular, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(Palette.background)
                .background(Palette.ink, in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// Upstream `formatDuration`: zero-padded minutes and seconds.
    private var formattedDuration: String {
        let total = max(0, Int(duration))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Composer modals and voice

/// The composer's sheets and covers: the file importer, the forge picker, the camera, and the
/// attachment viewer. R4 owns the sheet bodies.
struct ComposerSheets: ViewModifier {
    let controller: ChatController?
    let store: ConversationStore?
    @Binding var showFileImporter: Bool
    @Binding var showForgePicker: Bool
    @Binding var showCameraPicker: Bool
    @Binding var attachmentViewerImage: UIImage?
    let forgeIsGitLab: Bool
    let onFileURLs: ([URL]) -> Void
    let onCameraImage: (Data) -> Void
    let onForgePick: (ForgeSearchItem) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showFileImporter, allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls): onFileURLs(urls)
                case .failure(let error): controller?.showToast(error.localizedDescription)
                }
            }
            .sheet(isPresented: $showForgePicker) {
                if let controller {
                    ForgeSearchPicker(
                        session: controller.session, cwd: store?.agent?.cwd ?? "",
                        isMergeRequest: forgeIsGitLab,
                        onPick: { item in onForgePick(item) },
                        selectedIds: selectedIds)
                }
            }
            .sheet(isPresented: $showCameraPicker) {
                CameraCaptureView(
                    onCapture: { image in
                        showCameraPicker = false
                        guard let data = image.jpegData(compressionQuality: 1.0) else {
                            controller?.showToast("Couldn't read that photo.")
                            return
                        }
                        onCameraImage(data)
                    },
                    onCancel: { showCameraPicker = false }
                )
                .ignoresSafeArea()
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { attachmentViewerImage != nil },
                    set: { if !$0 { attachmentViewerImage = nil } })
            ) {
                if let image = attachmentViewerImage {
                    AttachmentImageViewer(image: image)
                }
            }
    }

    private var selectedIds: [String] {
        guard let controller, let store else { return [] }
        return controller.attachmentStore.items(for: store.agentId).compactMap { item in
            guard case .attached(let attachment) = item.phase else { return nil }
            return switch attachment {
            case .forgeChangeRequest(let forge): "change_request:\(forge.number)"
            case .forgeIssue(let forge): "issue:\(forge.number)"
            default: nil
            }
        }
    }
}

/// M15: realtime voice wiring. The engine feeds the store (mic PCM + level), the store feeds the
/// engine (next chunks + stop signals). Capture start/stop is driven by the phase.
struct ComposerVoiceWiring: ViewModifier {
    let controller: ChatController?

    func body(content: Content) -> some View {
        if let controller {
            Wired(content: content, controller: controller)
        } else {
            content
        }
    }

    private struct Wired<C: View>: View {
        let content: C
        let controller: ChatController

        var body: some View {
            content
                .task {
                    bind()
                    // The composer can appear while the lane is already waiting; `.onChange`
                    // never fires for the initial value.
                    if voice.isThinkingToneExpected { controller.voiceEngine.startThinkingTone() }
                }
                .onChange(of: voice.phase) { _, phase in
                    switch phase {
                    case .listening, .waiting, .playing:
                        Task { await startCapture() }
                    default:
                        controller.voiceEngine.stopCapture()
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
                }
                .onChange(of: voice.nextAudioChunk) { _, chunk in
                    guard let chunk else { return }
                    controller.voiceEngine.enqueue(chunk) { ok in
                        if ok {
                            voice.didPlayChunk(id: chunk.id)
                        } else {
                            voice.didFailChunk(id: chunk.id)
                        }
                    }
                }
                .onChange(of: voice.playbackStopRequested) { _, _ in
                    controller.voiceEngine.stopPlayback()
                }
                // M15: the thinking tone (upstream `reconcileCue`): only while the lane is waiting
                // for a reply and the daemon hears no speech. Timing lives in the engine.
                .onChange(of: voice.isThinkingToneExpected) { _, expected in
                    if expected {
                        controller.voiceEngine.startThinkingTone()
                    } else {
                        controller.voiceEngine.stopThinkingTone()
                    }
                }
                .onDisappear {
                    Task { await voice.stop() }
                    controller.voiceEngine.stopThinkingTone()
                    controller.voiceEngine.stopCapture()
                    UIApplication.shared.isIdleTimerDisabled = false
                }
        }

        private var voice: VoiceModeSession { controller.session.voiceSession }

        private func bind() {
            controller.voiceEngine.onCapturePCM = { data in
                voice.handleCapturePCM(data)
            }
            controller.voiceEngine.onVolumeLevel = { level in
                voice.handleCaptureVolume(level)
            }
            controller.voiceEngine.onInterruption = {
                voice.setMuted(true)
            }
        }

        private func startCapture() async {
            guard voice.isVoiceMode else { return }
            do {
                try await controller.voiceEngine.requestMicPermission()
                try await controller.voiceEngine.startCapture()
                UIApplication.shared.isIdleTimerDisabled = true
            } catch {
                controller.showToast(error.localizedDescription)
                await voice.stop()
            }
        }
    }
}
#endif
