#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension ClaudeChatView {
    // MARK: Composer

    /// §4.1: the pill at rest, the two-row card once it is focused or holds something. Every
    /// other composer control keys off this one value so the shape never half-changes.
    var composerExpanded: Bool {
        focused || !trimmedDraft.isEmpty || !trayItems.isEmpty || store.actionError != nil
            || voiceActiveForAgent || voice.phase == .starting
    }

    var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            slashMenu
            mentionMenu
            queueStack
            composerCard
        }
        .padding(.horizontal, composerExpanded ? 8 : 16)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: composerExpanded)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: slashQuery != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: mentionQuery != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isQueueNonEmpty)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: fastModeActive)
    }

    var composerCard: some View {
        let card = VStack(alignment: .leading, spacing: composerExpanded ? 8 : 0) {
            if composerExpanded { attachmentTray }
            if composerExpanded { dictationDeniedBanner }
            if composerExpanded, let error = store.actionError {
                Text(error)
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
            composerFieldRow
            if composerExpanded, voiceActiveForAgent || voice.phase == .starting {
                voiceBar
            }
            if composerExpanded { composerControlRow }
        }
        let framed = card
        .composerCardChrome(expanded: composerExpanded)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: composerExpanded)
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
        return withComposerVoiceWiring(withComposerSheets(framed))
    }

    /// Row 1. At rest this row *is* the pill: the add button, the placeholder, the mic and the
    /// voice control, one line high (§4.1). Expanded, the field takes the row alone and the
    /// controls move below it.
    ///
    /// The add button is an overlay, not a leading sibling: the field must keep the same
    /// structural position in both states or SwiftUI rebuilds it and the keyboard drops when the
    /// pill grows.
    @ViewBuilder var composerFieldRow: some View {
        HStack(spacing: 8) {
            composerTextField
                .padding(.leading, composerExpanded ? 0 : 44)
                .overlay(alignment: .leading) {
                    if !composerExpanded { composerAddMenu }
                }
            if !composerExpanded {
                dictateButton
                voiceModeButton
                if store.isRunning { composerSendControl }
            }
        }
    }

    /// Row 2: every chip the conversation has, then the trailing controls (§4.1).
    @ViewBuilder var composerControlRow: some View {
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

    @ViewBuilder var dictationDeniedBanner: some View {
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
                .accessibilityIdentifier("composer.dictation.settings")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    var composerTextField: some View {
        TextField(
            "", text: $store.draft,
            prompt: Text(composerPrompt)
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
        .accessibilityIdentifier("composer.draft")
    }

    var composerAddMenu: some View {
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
    }

    /// Refreshes PR status for the agent's workspace, then opens the issue/PR picker.
    func openForgePicker() {
        if let workspaceId = store.agent?.workspaceId,
            let workspace = session.workspaceDirectory.workspace(id: workspaceId)
        {
            let checkout = session.checkout(for: workspace)
            Task { await checkout.loadPrStatus() }
        }
        showForgePicker = true
    }

    var composerModelChip: some View {
        ComposerModelChip(modelLabel: modelChipTitle, thinkingLabel: thinkingLabel) {
            focused = false
            sheet = .controls
        }
    }

    @ViewBuilder var composerSendControl: some View {
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

    func withComposerSheets(_ content: some View) -> some View {
        content
        .fileImporter(
            isPresented: $showFileImporter, allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): attachFileURLs(urls)
            case .failure(let error): showToast(error.localizedDescription)
            }
        }
        .sheet(isPresented: $showForgePicker) {
            ForgeSearchPicker(
                session: session, cwd: store.agent?.cwd ?? "", isMergeRequest: forgeIsGitLab,
                onPick: { item in
                    toggleForgeAttachment(item)
                    showForgePicker = false
                },
                selectedIds: selectedForgeIds)
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
    }

    func withComposerVoiceWiring(_ content: some View) -> some View {
        content
        // M15: realtime voice wiring. The engine feeds the store (mic PCM + level), the
        // store feeds the engine (next chunks + stop signals). Capture start/stop is
        // driven by the phase; voice mode itself is store state.
        .task {
            bindVoiceEngine()
            // The composer can appear while the lane is already waiting; `.onChange`
            // never fires for the initial value.
            if voice.isThinkingToneExpected { voiceEngine.startThinkingTone() }
        }
        .onChange(of: voice.phase) { _, phase in
            switch phase {
            case .listening, .waiting, .playing:
                Task { await startVoiceCapture() }
            default:
                voiceEngine.stopCapture()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .onChange(of: voice.nextAudioChunk) { _, chunk in
            guard let chunk else { return }
            voiceEngine.enqueue(chunk) { ok in
                if ok {
                    voice.didPlayChunk(id: chunk.id)
                } else {
                    voice.didFailChunk(id: chunk.id)
                }
            }
        }
        .onChange(of: voice.playbackStopRequested) { _, _ in
            voiceEngine.stopPlayback()
        }
        // M15: the thinking tone (upstream `reconcileCue`): only while the lane is waiting
        // for a reply and the daemon hears no speech. Timing lives in the engine.
        .onChange(of: voice.isThinkingToneExpected) { _, expected in
            if expected {
                voiceEngine.startThinkingTone()
            } else {
                voiceEngine.stopThinkingTone()
            }
        }
        .onDisappear {
            Task { await voice.stop() }
            voiceEngine.stopThinkingTone()
            voiceEngine.stopCapture()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        // M17: drop a file row (Files tree / Changes list) onto the composer to attach it
        // as a workspace-file mention. The long-press "Add to chat" path stays.
        .dropDestination(for: String.self) { items, _ in
            guard let path = items.first else { return false }
            insertFileMention(path)
            return true
        }
    }

    // MARK: Voice mode (M15)

    private var voice: VoiceModeSession { session.voiceSession }
    private var voiceActiveForAgent: Bool { voice.isVoiceMode(for: store.agentId) }

    /// The mic-disc voice button, gated on the daemon saying realtime voice is usable.
    /// While active it toggles mute (upstream disc behavior); otherwise it starts voice
    /// mode (blocked while a turn runs — interrupt the agent first).
    @ViewBuilder private var voiceModeButton: some View {
        if session.voiceSession.isVoiceAvailable {
            Button {
                toggleVoiceMode()
            } label: {
                Image(systemName: voiceActiveForAgent && voice.isMuted ? "mic.slash.fill" : "waveform.and.mic")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(voiceActiveForAgent ? .white : ClaudePalette.ink)
                    .background(voiceActiveForAgent ? ClaudePalette.orange : ClaudePalette.chip, in: .circle)
            }
            .accessibilityLabel(
                voiceActiveForAgent
                    ? (voice.isMuted ? "Unmute voice mode" : "Mute Voice mode") : "Enable Voice mode")
            .accessibilityIdentifier("composer.voiceMode")
            .disabled(voice.isVoiceSwitching)
        }
    }

    /// The live voice row: mute toggle, volume meter, stop/interrupt (upstream wording).
    @ViewBuilder private var voiceBar: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.selection()
                voice.setMuted(!voice.isMuted)
            } label: {
                Image(systemName: voice.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.white)
                    .background(voice.isMuted ? ClaudePalette.failureInk : ClaudePalette.chip, in: .circle)
            }
            .accessibilityLabel(voice.isMuted ? "Unmute voice" : "Mute voice")
            .accessibilityIdentifier("composer.voice.mute")

            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    let height = [8.0, 13.0, 18.0, 13.0, 8.0][index]
                    Capsule()
                        .fill(ClaudePalette.ink.opacity(0.85))
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
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.white)
                    .background(ClaudePalette.failureInk, in: .circle)
            }
            .accessibilityLabel("Stop realtime voice and interrupt turn")
            .accessibilityIdentifier("composer.voice.stop")
            // Reachable while `.starting` too: a slow/hung `set_voice_mode` must not trap
            // the user in voice mode with only a disabled stop button.
            .disabled(voice.phase == .stopping)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func toggleVoiceMode() {
        if voice.isVoiceMode(for: store.agentId) {
            voice.setMuted(!voice.isMuted)
            return
        }
        if store.isRunning {
            showToast("Interrupt the agent before starting voice mode")
            return
        }
        Haptics.selection()
        Task {
            let ok = await voice.start(agentId: store.agentId)
            if !ok {
                if voice.missingModelIds.isEmpty {
                    showToast(voice.error ?? "Voice mode is not available.")
                } else {
                    showToast("Voice needs models that aren't downloaded. Download them in Settings → Voice.")
                }
            }
        }
    }

    /// Mic PCM + level from the engine into the store; interruption mutes.
    private func bindVoiceEngine() {
        voiceEngine.onCapturePCM = { data in
            voice.handleCapturePCM(data)
        }
        voiceEngine.onVolumeLevel = { level in
            voice.handleCaptureVolume(level)
        }
        voiceEngine.onInterruption = {
            voice.setMuted(true)
        }
    }

    private func startVoiceCapture() async {
        guard voice.isVoiceMode else { return }
        do {
            try await voiceEngine.requestMicPermission()
            try voiceEngine.startCapture()
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            showToast(error.localizedDescription)
            await voice.stop()
        }
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
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .padding(.trailing, 104)
            .padding(.top, 1)
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
                .foregroundStyle(ClaudePalette.ink)
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
            switch item.phase {
            case .done(let attachment): return .uploadedFile(attachment)
            case .attached(let attachment): return attachment
            case .pending, .uploading, .failed: return nil
            }
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
extension ClaudeChatView {
    /// The dictation mic, split out of the composer row so the type checker sees one small
    /// expression at a time.
    var dictateButton: some View {
        ComposerMicButton(isListening: dictation.isListening, level: Double(dictation.level)) {
            if dictation.isListening {
                dictation.stop(keepingDraft: true)
            } else {
                dictation.toggle(currentDraft: store.draft)
            }
        }
    }
}

// MARK: - Shared composer pieces

/// The composer's card: a one-line pill at rest, a lifted card once open (UX-SPEC §4.1). Shared
/// by the live conversation and the draft so both grow the same way.
struct ComposerCardChrome: ViewModifier {
    let expanded: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, expanded ? 8 : 12)
            .padding(.vertical, expanded ? 8 : 0)
            .frame(minHeight: 48)
            .background(
                ClaudePalette.composer,
                in: .rect(cornerRadius: expanded ? 27 : 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: expanded ? 27 : 24, style: .continuous)
                    .stroke(ClaudePalette.composerBorder, lineWidth: 0.7)
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
    var action: () -> Void

    private let typography = ClaudeTypography()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let providerLabel {
                    ProviderGlyph(label: providerLabel)
                }
                Text(modelLabel)
                if let thinkingLabel {
                    Text(thinkingLabel).foregroundStyle(ClaudePalette.secondaryInk)
                }
            }
            .font(typography.sans(14))
            .foregroundStyle(ClaudePalette.ink)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(ClaudePalette.chip, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model, thinking and mode")
        .accessibilityIdentifier("composer.model")
    }
}

/// The provider's mark in the model chip's leading edge. Host catalogues carry per-provider brand
/// SVGs (`ProviderSnapshotEntry.iconSvg`), which this app does not render; the glyph is a two-
/// letter monogram on a small tile instead, so it reads the same for every provider and stays
/// monochrome (§0.1).
struct ProviderGlyph: View {
    let label: String

    var body: some View {
        Text(monogram)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(ClaudePalette.secondaryInk)
            .frame(width: 16, height: 16)
            .background(ClaudePalette.panel, in: .rect(cornerRadius: 4, style: .continuous))
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

/// The dictation mic: ink on `chip`, accented and pulsing while it listens. The draft and the live
/// conversation draw the same control.
struct ComposerMicButton: View {
    let isListening: Bool
    /// 0…1 input level while listening.
    let level: Double
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: isListening ? "mic.fill" : "mic")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(isListening ? Color.white : ClaudePalette.ink)
                .background(isListening ? ClaudePalette.orange : ClaudePalette.chip, in: .circle)
                .scaleEffect(scale)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
        }
        .accessibilityLabel(isListening ? "Stop dictation" : "Dictate")
        .accessibilityIdentifier("composer.dictate")
    }

    private var scale: CGFloat {
        guard isListening, !reduceMotion else { return 1 }
        return 1 + CGFloat(level) * 0.18
    }
}
#endif
