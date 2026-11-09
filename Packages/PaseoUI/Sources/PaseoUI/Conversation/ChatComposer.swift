#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension ClaudeChatView {
    // MARK: Composer

    var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            slashMenu
            mentionMenu
            queueStack
            composerCard
        }
        .padding(.horizontal, focused ? 8 : 16)
        .animation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.feedback), value: focused)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: slashQuery != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: mentionQuery != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isQueueNonEmpty)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: !trayItems.isEmpty)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: fastModeActive)
    }

    var composerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            attachmentTray
            if dictation.isDenied {
                HStack(spacing: 8) {
                    Image(systemName: "mic.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(ClaudePalette.failureInk)
                    Text("Dictation is off. Enable Microphone and Speech Recognition in Settings.")
                        .font(.system(size: 12))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button("Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ClaudePalette.orange)
                    .accessibilityLabel("Open Settings")
                    .accessibilityIdentifier("composer.dictation.settings")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            if let error = store.actionError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
            TextField(
                "", text: $store.draft,
                prompt: Text(composerPrompt)
                    .foregroundStyle(ClaudePalette.secondaryInk),
                axis: .vertical
            )
            .font(typography.sans(18))
            .lineLimit(1...12)
            .fixedSize(horizontal: false, vertical: true)
            .focused($focused)
            .tint(ClaudePalette.orange)
            .padding(.horizontal, 6)
            .padding(.top, 7)
            .accessibilityIdentifier("composer.draft")
            HStack(spacing: 8) {
                Menu {
                    PhotosPicker(
                        selection: $photoSelection, maxSelectionCount: 10, matching: .images
                    ) {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                    if cameraAvailable {
                        Button("Camera", systemImage: "camera") { showCameraPicker = true }
                    }
                    Button("Files", systemImage: "folder") { showFileImporter = true }
                    Button("Mention a file", systemImage: "at") { mentionFile() }
                    Divider()
                    Button("New agent", systemImage: "plus.bubble") {
                        newAgent(draft: store.draft)
                    }
                    Button("Copy agent ID", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = store.agentId
                        Haptics.selection()
                        showToast("Agent ID copied")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(ClaudePalette.ink)
                        .background(ClaudePalette.chip, in: .circle)
                }
                .accessibilityLabel("Add to agent")
                Button {
                    focused = false
                    sheet = .controls
                } label: {
                    HStack(spacing: 3) {
                        Text(modelChipTitle)
                        if let thinkingLabel {
                            Text(thinkingLabel).foregroundStyle(ClaudePalette.secondaryInk)
                        }
                    }
                    .font(typography.sans(14))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(ClaudePalette.chip, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Model, thinking and mode")
                .accessibilityIdentifier("composer.model")
                fastModeChip
                Spacer(minLength: 0)
                contextMeter
                Button {
                    if dictation.isListening {
                        dictation.stop(keepingDraft: true)
                    } else {
                        Task { await dictation.toggle(currentDraft: store.draft) }
                    }
                } label: {
                    Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(dictation.isListening ? .white : ClaudePalette.ink)
                        .background(
                            dictation.isListening ? ClaudePalette.orange : ClaudePalette.chip,
                            in: .circle)
                        .scaleEffect(
                            dictation.isListening && !reduceMotion
                                ? 1 + CGFloat(dictation.level) * 0.18 : 1)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: dictation.level)
                }
                .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate")
                .accessibilityIdentifier("composer.dictate")
                if store.isRunning && trimmedDraft.isEmpty {
                    roundButton("stop.fill", label: "Stop response", color: ClaudePalette.ink, ink: ClaudePalette.background) {
                        Task { await store.cancel() }
                    }
                    .accessibilityIdentifier("composer.stop")
                } else {
                    QueueSendButton(
                        isRunning: store.isRunning, canSend: canSendMessage
                    ) {
                        tapSend()
                    } onQueue: {
                        longPressSend()
                    }
                    .accessibilityIdentifier("composer.send")
                }
            }
        }
        .padding(8)
        .padding(.top, 1)
        .background(ClaudePalette.composer, in: .rect(cornerRadius: 27))
        .overlay {
            RoundedRectangle(cornerRadius: 27).stroke(ClaudePalette.composerBorder, lineWidth: 0.7)
        }
        .onChange(of: composerFocusRequested.wrappedValue) { _, requested in
            guard requested else { return }
            focused = true
            composerFocusRequested.wrappedValue = false
        }
        // M8b: expand control for tall drafts, left of the crab's spot.
        .overlay(alignment: .topTrailing) { expandComposerButton }
        // The crab stands on the card's top edge, flush with its trailing edge.
        .overlay(alignment: .topTrailing) { mascotCrab }
        .fullScreenCover(isPresented: $showFullScreenComposer) {
            FullScreenComposer(draft: $store.draft, isRunning: store.isRunning) { send() }
        }
        .fileImporter(
            isPresented: $showFileImporter, allowsMultipleSelection: true,
            allowedContentTypes: [.item]
        ) { result in
            switch result {
            case .success(let urls): attachFileURLs(urls)
            case .failure(let error): showToast(error.localizedDescription)
            }
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraCaptureView(
                onCapture: { image in
                    showCameraPicker = false
                    guard let data = image.jpegData(compressionQuality: 1.0) else {
                        showToast("Couldn't read that photo.")
                        return
                    }
                    attachImageData(data, fileName: "photo-\(UUID().uuidString.prefix(8)).jpg")
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
        .onPasteCommand(of: [.image], perform: handlePastedItems)
    }

    /// M8b: the expand control — visible only when the draft is ~5 lines tall or more.
    @ViewBuilder private var expandComposerButton: some View {
        if DraftMetrics.isTall(store.draft) {
            Button {
                Haptics.selection()
                showFullScreenComposer = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .frame(width: 28, height: 28)
                    .background(ClaudePalette.chip, in: .circle)
            }
            .padding(.trailing, 112)
            .padding(.top, 9)
            .accessibilityLabel("Expand composer")
            .transition(.opacity)
        }
    }

    var trimmedDraft: String {
        store.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var modelChipTitle: String {
        modelLabel ?? "Model"
    }

    /// The provider's fast-mode toggle, when offered. Matched by the upstream id
    /// `FAST_MODE_FEATURE_ID = "fast_mode"` (`packages/app/src/agent-controls/policy.ts:4`).
    var fastModeFeature: AgentFeature.Toggle? {
        guard let features = store.agent?.features else { return nil }
        for feature in features {
            if case .toggle(let toggle) = feature, toggle.id == "fast_mode" {
                return toggle
            }
        }
        return nil
    }

    var fastModeActive: Bool { fastModeFeature?.value == true }

    /// The quiet fast-mode chip in the toolbar: visible only while fast mode is on;
    /// tapping turns it off. Bolt glyph, accent ink at low emphasis.
    @ViewBuilder private var fastModeChip: some View {
        if fastModeActive {
            Button {
                Haptics.selection()
                Task { await store.setFeatureToggle(featureId: "fast_mode", value: false) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Fast")
                        .font(typography.sans(13, weight: .semibold))
                }
                .foregroundStyle(ClaudePalette.orange.opacity(0.8))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(ClaudePalette.chip, in: .capsule)
            }
            .accessibilityLabel("Fast mode on; turn off")
            .accessibilityIdentifier("composer.fastmode")
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    /// The quiet context-window meter in the toolbar: the host's window occupancy, visible
    /// only when the agent reports a window. Tapping opens the details sheet.
    @ViewBuilder private var contextMeter: some View {
        if let percent = store.contextUsage?.percentUsed,
            store.contextUsage?.usedTokens != nil,
            store.contextUsage?.maxTokens != nil
        {
            Button {
                Haptics.selection()
                showContextSheet = true
            } label: {
                ClaudeMeterRing(percent: percent, size: 16, lineWidth: 1.5)
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Context window, \(Int(percent.rounded())) percent used")
            .accessibilityIdentifier("composer.contextMeter")
        }
    }

    var thinkingLabel: String? {
        guard let agent = store.agent, let model = agent.effectiveThinkingOptionId ?? agent.thinkingOptionId else {
            return nil
        }
        guard let modelId = agent.model else { return nil }
        return session.agentControl.thinkingOptions(forProvider: agent.provider, modelId: modelId)
            .first(where: { $0.id == model })?.label
    }

    /// Tap on the send button. While a turn is running, the `paseo.defaultSend` setting decides:
    /// steer (default), queue, or interrupt. Idle, it always starts a new turn.
    var defaultSendBehavior: DefaultSendBehavior {
        DefaultSendBehavior(rawValue: defaultSend) ?? .steer
    }

    func tapSend() {
        if defaultSendBehavior == .queue, store.isRunning {
            queueDraft()
            return
        }
        send(behavior: store.isRunning && defaultSendBehavior == .interrupt ? "interrupt" : nil)
    }

    /// Long-press on the send button: the opposite of the default between steer and queue
    /// (interrupt has no opposite there, so it queues).
    func longPressSend() {
        switch defaultSendBehavior {
        case .steer, .interrupt: queueDraft()
        case .queue: send()
        }
    }

    func send(behavior: String? = nil) {
        dictation.stop(keepingDraft: true)
        let text = trimmedDraft
        // Send is disabled while an upload is in flight; the tray keeps the failed pills,
        // everything ready rides this send.
        let readyAttachments = trayItems.compactMap { item -> AgentAttachment? in
            if case .done(let attachment) = item.phase { return .uploadedFile(attachment) }
            return nil
        }
        guard !text.isEmpty || !readyAttachments.isEmpty else { return }
        guard !hasUploadingAttachment else { return }
        SavedDraftStore.clear(store.agentId)
        focused = false
        // M7d chat-anchor: your message pins to the top; tail-follow takes over once the
        // answer grows past the bottom.
        anchoringToAnswer = true
        isFollowing = false
        Haptics.send()
        Task {
            await store.sendWithAttachments(text, attachments: readyAttachments, behavior: behavior)
            if store.actionError == nil {
                attachmentStore.consumeDoneAttachments(for: store.agentId)
            }
        }
    }

    func roundButton(
        _ symbol: String, label: String, color: Color, ink: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(ink)
                .background(color, in: .circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Reads a workspace image through its checkout store (the same instance the panel shares),
    /// for bare absolute/`~` image paths in assistant prose. Returns nil when the workspace of
    /// this conversation isn't open in the directory — those render as path chips.
    var localImageLoader: ((String) async -> UIImage?)? {
        guard let workspaceId = store.agent?.workspaceId else { return nil }
        let session = self.session
        return { path in
            guard let descriptor = session.workspaceDirectory.workspace(id: workspaceId) else {
                return nil
            }
            let checkout = session.checkout(for: descriptor)
            await checkout.files.read(path, maxBytes: 8 * 1024 * 1024)
            guard checkout.files.phase == .ready,
                let file = checkout.files.file,
                file.kind == .image,
                let content = file.content,
                let data = Data(base64Encoded: content),
                let image = UIImage(data: data)
            else { return nil }
            return image
        }
    }

    func handleMarkdown(_ action: MarkdownAction) {
        switch action {
        case .openLink(let url):
            openURL(url)
        case .copyCode(let code):
            UIPasteboard.general.string = code
            Haptics.selection()
            showToast("Code copied")
        default:
            break
        }
    }

    func showToast(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = nil }
        }
    }
}
#endif
