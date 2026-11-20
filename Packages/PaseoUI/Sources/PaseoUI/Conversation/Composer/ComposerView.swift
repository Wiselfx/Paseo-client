#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The one composer (R6 §5): the conversation's two-row card, and the draft's card once it is
/// expanded. Every derived value (`canSend`, `slashQuery`, `mentionQuery`) is computed here, so
/// the rest of the screen never reads the draft. The one exception is the expand control's
/// visibility, which the field itself decides from its own layout (`ComposerUITextView`) because
/// only the text layout knows the draft's real line count (H3 §2).
///
/// **Reads:** the text binding, `store.isRunning`, `store.actionError`, `store.agent` (model,
/// provider, features), and the controller's slash / mention / queue / attachment / dictation /
/// voice state. The context meter reads `store.contextUsage` itself, one control wide
/// (`ComposerContextMeter`, H3 §1).
struct ComposerView: View {
    let mode: ComposerMode
    /// The conversation; nil in draft mode.
    let store: ConversationStore?
    /// The open agent's controller; nil in draft mode.
    let controller: ChatController?
    /// Draft mode: the session's stores (catalogue for create, the upload channel, agents).
    let draftHost: HostSession?
    /// Draft mode: the shell creates the agent and swaps its conversation in (D2 §3).
    let onSubmit: ((DraftSubmission) -> Void)?

    /// The composer's text, read and written through the store the mode names. Not a `Binding`
    /// handed in by the parent (W1): a binding whose getter reads the draft, created in the parent's body
    /// is evaluated by SwiftUI when it compares the view's inputs, which made `store.draft` a
    /// dependency of `ChatScreen.body` and re-ran the screen, the composer and the bars on every
    /// keystroke. Here the read happens in this view's own body only.
    private var text: String {
        get {
            switch mode {
            case .conversation: store?.draft ?? ""
            case .draft(let draft): draft.text
            }
        }
        nonmutating set {
            switch mode {
            case .conversation: store?.draft = newValue
            case .draft(let draft): draft.text = newValue
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding(get: { text }, set: { text = $0 })
    }
    /// The composer's focus. A plain `Bool`, not `@FocusState`: nothing SwiftUI-focusable is
    /// bound to it (`ComposerTextView` is a `UITextView`), and SwiftUI drops writes to a
    /// `FocusState` with no view bound to it — which is what resigned the field on every
    /// keystroke (E1 §1).
    @Binding var focused: Bool

    /// Draft mode's own tray: there is no agent id to key the shared store by yet, and a draft
    /// uploads through the session's channel before the create request.
    @State private var localTray: [ComposerAttachmentItem] = []
    /// The draft's tray while creation is in flight: it comes back if the shell reports a
    /// failure (D2 §3). Never written after an `await`.
    @State private var stashedTray: [ComposerAttachmentItem] = []
    @State private var uploadPumpRunning = false
    @State private var localAttachmentError: String?
    /// The draft's own dictation, built on first use (W1): `State(initialValue:)` runs its argument on
    /// every parent pass, and a conversation never touches this one.
    @State private var draftDictationHolder = LazyDictation()
    private var draftDictation: DictationController { draftDictationHolder.controller }
    @State private var showDraftControls = false
    @State private var showDraftFullScreen = false

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showCameraPicker = false
    @State private var showFileImporter = false
    @State private var showForgePicker = false
    @State private var attachmentViewerImage: UIImage?
    @State private var surfaceHeight: CGFloat = 0
    /// Whether the tall draft's expand control is in the card's corner, and with it whether the
    /// field reserves the corner's trailing column. **Written by the field** from its own laid-out
    /// line count, only when the answer flips: sticky between `ComposerMetrics.expandShowLines`
    /// and `expandHideLines` (H3 §2), so a word wrapping at the threshold cannot flicker the
    /// control and re-flow the text on consecutive keystrokes.
    @State private var expandVisible = false

    @Environment(\.composerFocusRequested) private var composerFocusRequested
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DefaultSendBehavior.storageKey) private var defaultSend = DefaultSendBehavior.steer.rawValue

    init(
        mode: ComposerMode, store: ConversationStore, controller: ChatController,
        focused: Binding<Bool>
    ) {
        self.mode = mode
        self.store = store
        self.controller = controller
        self.draftHost = nil
        self.onSubmit = nil
        self._focused = focused
    }

    /// The draft screen's composer: the same card, before its agent exists (R6 §5).
    init(
        draft: DraftSession, session: HostSession, onSubmit: @escaping (DraftSubmission) -> Void,
        focused: Binding<Bool>
    ) {
        self.mode = .draft(draft)
        self.store = nil
        self.controller = nil
        self.draftHost = session
        self.onSubmit = onSubmit
        self._focused = focused
    }

    var body: some View {
        let _ = PaseoPerf.body("Composer")
        let _ = PaseoPerf.why(Self.self)
        // Spacing 0: each piece above the card carries its own 6 pt, so an absent one leaves no gap.
        VStack(alignment: .leading, spacing: 0) {
            if !isDraft, let store, let controller {
                // The only part of the composer that reads the text on every keystroke.
                ComposerMenus(store: store, controller: controller, focused: $focused)
                queueStack
            }
            composerCard
        }
        .padding(.horizontal, isDraft && !composerExpanded ? Space.lg : ComposerMetrics.sideInset)
        // While the field is focused the keyboard is up, and the card keeps 8 pt above it, as
        // Claude's does (N3 C). Focus is the flag the field keeps in sync with the keyboard; no
        // keyboard arithmetic, and nothing changes while the keyboard is down.
        .padding(.bottom, focused ? Space.sm : 0)
        .animation(Motion.disclosure.resolved(reduceMotion: reduceMotion), value: focused)
        // The pill's wider margin is part of the same disclosure as its height and corner: the
        // card widens while it grows, so the field slides instead of jumping (E1 §4).
        .animation(
            Motion.disclosure.resolved(reduceMotion: reduceMotion), value: composerExpanded)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { height in
            surfaceHeight = height
        }
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: queueIsEmpty == false)
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: fastModeActive)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            handlePickedPhotos(items)
        }
        .onChange(of: draftSession?.error) { _, error in
            // Creation failed in the shell: the draft stayed on screen, so the tray comes back.
            // Anything attached in the meantime wins over the stash.
            guard error != nil, !stashedTray.isEmpty else { return }
            if localTray.isEmpty { localTray = stashedTray }
            stashedTray = []
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

    /// Whether the text is only whitespace. Read from the store's flag, which changes only when the
    /// answer flips: the chrome below never depends on the text itself, so a keystroke re-runs
    /// only `ComposerMenus` and the field.
    private var draftIsBlank: Bool {
        switch mode {
        case .conversation: store?.draftIsBlank ?? true
        case .draft(let draft): draft.textIsBlank
        }
    }

    /// One O(lines) pass per text change, and only while the draft is being typed into: what the
    /// expand control's visibility is decided from (H3 §2).
    private var isDraft: Bool {
        if case .draft = mode { return true }
        return false
    }

    /// Whether the corner expand control is on screen: the field's laid-out line count said the
    /// draft is tall (`ComposerTextView.expandVisible`, H3 §2) and the card is open — the at-rest
    /// pill is one line tall and its own mic owns that corner.
    private var expandControlShown: Bool { expandVisible && composerExpanded }

    private var draftSession: DraftSession? {
        if case .draft(let draft) = mode { return draft }
        return nil
    }

    /// §4.1: the draft's one-line pill at rest becomes the two-row card once focused, holding
    /// text, an attachment, an error or dictation. A live conversation is always the card (V5 §4.4).
    private var composerExpanded: Bool {
        guard isDraft else { return true }
        return focused || !draftIsBlank || !trayItems.isEmpty || errorText != nil
            || (activeDictation?.isListening ?? false)
    }

    /// The dictation controller that belongs to this composer: the conversation's or a draft's own.
    private var activeDictation: DictationController? {
        controller?.dictation ?? draftDictation
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
        if !draftIsBlank { return true }
        return !readyAttachments.isEmpty
    }

    /// What the card shows under the field when something went wrong.
    private var errorText: String? {
        if let store { return store.actionError }
        return localAttachmentError ?? draftSession?.error
    }

    /// Asked once: the answer cannot change while the app runs, and the call costs 1 to 2 ms, which
    /// the composer's body paid on every evaluation (W1).
    private static let cameraIsAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
    private var cameraAvailable: Bool { Self.cameraIsAvailable }

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
        VStack(alignment: .leading, spacing: composerExpanded ? ComposerMetrics.fieldRowGap : 0) {
            if let dictation = activeDictation, dictation.isListening {
                dictationOverlay(dictation)
            } else {
                if composerExpanded { attachmentTray }
                if composerExpanded { dictationDeniedBanner }
                if composerExpanded { dictationFailureBanner }
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
        // A request set before this composer mounted (the new-agent deep link
        // creates its draft first): consume it on appear, or it would never fire.
        .onAppear {
            guard composerFocusRequested.wrappedValue else { return }
            focused = true
            composerFocusRequested.wrappedValue = false
        }
        .onChange(of: controller?.dismissKeyboardRequest) { _, _ in
            focused = false
        }
        // The crab stands on the card's top edge, flush with its trailing edge.
        .overlay(alignment: .topTrailing) { mascotCrab }
        .sheet(isPresented: $showDraftControls) {
            if let draft = draftSession, let session = draftHost {
                DraftControlsSheet(session: session, draft: draft)
            }
        }
        .fullScreenCover(isPresented: fullScreenComposerBinding) {
            FullScreenComposer(
                draft: textBinding,
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
    ///
    /// The expand control hangs off this row's trailing corner: measuring from the field is what
    /// keeps it exactly over the text it takes room from, whatever sits above (H3 §2).
    private var fieldRow: some View {
        Group {
            if isDraft {
                HStack(spacing: ComposerMetrics.controlSpacing) {
                    composerTextField
                        .padding(.leading, composerExpanded ? 0 : ComposerMetrics.hitSize)
                        .overlay(alignment: .leading) {
                            if !composerExpanded { composerAddMenu }
                        }
                    if !composerExpanded { dictateButton }
                }
            } else {
                composerTextField
            }
        }
        .overlay(alignment: .topTrailing) {
            expandComposerButton
                // Up into the card's padding, the same 8 pt the card's own padding is, so the
                // control sits in the card's corner — not 8 pt below it (E1 §4).
                .padding(.top, -ComposerMetrics.verticalInset)
                // Opacity only: the card keeps its height and the field keeps its width, so the
                // control fades in over the reserve the field already carries.
                .animation(
                    Motion.fade.resolved(reduceMotion: reduceMotion), value: expandControlShown)
        }
    }

    private var composerTextField: some View {
        // D2 §2: a `UITextView` under SwiftUI, so a pasted image has somewhere to land. The face,
        // the ink tint, the placeholder, the grow-to-cap height and the focus binding are all
        // applied there; ⌘↩ still belongs to the send button.
        ComposerTextView(
            text: textBinding,
            isFocused: $focused,
            placeholder: placeholder,
            lineLimit: composerFieldLineLimit,
            // The field decides this from its own layout and writes it only when it flips, so no
            // keystroke scans the draft to guess a line count (H3 §2).
            expandVisible: $expandVisible,
            // The field gives the control its column back while the control is on screen: written
            // only when the control appears or disappears, never per keystroke.
            reservesCornerControl: expandControlShown
        ) { images in
            attachPastedImages(images)
        }
        .accessibilityIdentifier("composer.draft")
    }

    /// One string in both modes, from upstream `composer.placeholders.mobile` (en.ts:117).
    private var placeholder: String {
        controller?.composerPrompt ?? "Message, @files, /commands"
    }

    /// Upstream `message.dictation.failed`: "Dictation failed: {{error}}", with `retry`.
    @ViewBuilder private var dictationFailureBanner: some View {
        if let failure = activeDictation?.failure {
            InlineBanner(
                .failure, title: failure.title, message: failure.message, systemImage: "mic.slash",
                action: ("Retry dictation", {
                    activeDictation?.dismissFailure()
                    if let dictation = activeDictation {
                        dictation.toggle(currentDraft: text)
                    }
                }))
                .accessibilityIdentifier("composer.dictation.failed")
        }
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
        HStack(spacing: ComposerMetrics.controlSpacing) {
            composerAddMenu
            composerModelChip
            fastModeChip
            Spacer(minLength: 0)
            contextMeter
            dictateButton
            composerPrimary
        }
        // The 44 pt hit frames hang into the card's padding, so the 36 pt circles sit 8 pt from
        // the card's edge, concentric with its corner (E1 §4).
        .padding(.horizontal, -ComposerMetrics.controlOverhang)
        .padding(.bottom, -ComposerMetrics.controlOverhang)
        // No animation on the meter: it never appears or disappears, and the reading changes
        // inside `ComposerContextMeter`, not here (H3 §1).
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
            // The field takes ⌘V; the menu offers the same thing for discovery, and attaches
            // every image on the pasteboard (D2 §2).
            if PasteboardImageState.shared.hasImages {
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
                .frame(width: ComposerMetrics.controlSize, height: ComposerMetrics.controlSize)
                .foregroundStyle(Palette.ink)
                .background(Palette.chip, in: .circle)
                .frame(width: ComposerMetrics.hitSize, height: ComposerMetrics.hitSize)
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
                .padding(.horizontal, ComposerMetrics.chipPadding)
                .frame(minHeight: ComposerMetrics.controlSize)
                .background(Palette.chip, in: .capsule)
                .frame(minHeight: ComposerMetrics.hitSize)
            }
            .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
            .accessibilityLabel("Fast mode on; turn off")
            .accessibilityIdentifier("composer.fastmode")
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    /// The meter's slot in the control row (H3 §1). In a conversation it is **always** occupied:
    /// the ring is there before the provider reports a window and stays at any percentage, so the
    /// row cannot reflow when usage arrives or when 70 % is crossed. The ring, its number and the
    /// empty track live in `ComposerContextMeter`, which is also the only view that reads the
    /// usage (R-1): this body never reads it, and the ring redraws only when the integer percent
    /// changes.
    ///
    /// The draft has no agent and will never have a window, so it has no slot: an empty 44 pt
    /// column would only take width from the model chip for the whole of the draft's life. Nothing
    /// moves at the hand-off either — the shell swaps the draft screen for the conversation, so the
    /// two rows are never on screen together.
    @ViewBuilder private var contextMeter: some View {
        if let store, !isDraft {
            ComposerContextMeter(store: store) {
                controller?.showContextSheet = true
            }
        }
    }

    /// Nothing while voice mode owns the mic (E1 §3): a second owner would set the session's
    /// category to `.measurement` and its teardown would deactivate voice mode's session.
    @ViewBuilder private var dictateButton: some View {
        // Also hidden while the lane is starting: `isVoiceMode` only becomes true once the daemon
        // accepts, and dictation must never own the mic inside that window — it would switch the
        // session category out from under the capture that is about to start.
        if !voiceActiveForAgent, voice?.phase != .starting, let dictation = activeDictation {
            ComposerMicButton(isListening: dictation.isListening) {
                if dictation.isListening {
                    dictation.stop(keepingDraft: true)
                } else {
                    dictation.toggle(currentDraft: text)
                }
            }
        }
    }

    private func dictationOverlay(_ dictation: DictationController) -> some View {
        DictationOverlay(
            buffer: dictation.waveform,
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

    // MARK: The primary

    /// Voice mode first (it owns the lane), then anything to send, then a running turn, then the
    /// idle states. A truncated draft still sends: only `canSend` decides that it can.
    private var primaryState: ComposerPrimaryState {
        if voiceActiveForAgent { return .voiceActive }
        // An upload in flight has nothing to send yet; the table's disabled look says so without
        // inventing a second one.
        if hasUploadingAttachment { return .unavailable }
        if !draftIsBlank || !readyAttachments.isEmpty { return .send }
        if store?.isRunning == true { return .stop }
        if voiceCanStart { return .voice }
        return .unavailable
    }

    /// The host advertises realtime voice — even when it cannot run it this second (a missing
    /// model, a provider setting). The control stays live so a tap says why (E1 §3.5), instead
    /// of a disabled circle that swallows the tap and explains nothing.
    private var voiceCanStart: Bool {
        guard let voice else { return false }
        return voice.isVoiceAvailable || !voice.unavailableReason.isEmpty
    }

    private var primaryIsEnabled: Bool {
        switch primaryState {
        case .unavailable: return false
        case .send: return canSend
        case .voice, .voiceActive: return voice?.isVoiceSwitching != true
        case .stop: return true
        }
    }

    private var composerPrimary: some View {
        let onQueue: (() -> Void)? = controller == nil ? nil : { longPressSend() }
        return ComposerPrimaryButton(
            state: primaryState,
            isEnabled: primaryIsEnabled,
            isMuted: voice?.isMuted ?? false,
            waveform: primaryState == .voiceActive ? controller?.voiceEngine.waveform : nil,
            reduceMotion: reduceMotion,
            onTap: primaryTap,
            onQueue: onQueue)
    }

    private func primaryTap() {
        switch primaryState {
        case .voice, .voiceActive:
            toggleVoiceMode()
        case .stop:
            Task { await store?.cancel() }
        case .send, .unavailable:
            tapSend()
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
        if let draft = draftSession {
            guard canSend else { return }
            draftDictation.stop(keepingDraft: true)
            localAttachmentError = nil
            draft.clearError()
            Haptics.send()
            // The tray leaves the field before the hop, with a copy kept for a failed create:
            // once the shell swaps the conversation in, this view's state is never written again
            // (D2 §3). The shell runs the create from a task it owns.
            let submission = DraftSubmission(text: draft.text, attachments: readyAttachments)
            stashedTray = localTray
            localTray = []
            onSubmit?(submission)
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
        // The picker's files are read off the main actor (`PickedFileLoader`): a 40 MB file, or an
        // iCloud file that still has to download, used to freeze this screen inside
        // `Data(contentsOf:)`. Each tile is in the tray from the tap — `.decoding` also holds Send
        // while the bytes load, so a tap cannot overtake the file.
        Task {
            for url in urls {
                let name = url.lastPathComponent
                var item = ComposerAttachmentItem(
                    fileName: name, mimeType: "application/octet-stream", byteCount: 0,
                    data: Data(), thumbnail: nil, phase: .decoding)
                localTray.append(item)
                switch await PickedFileLoader.load(url, maxBytes: ConversationUpload.maxBytes) {
                case .success(let file):
                    item.mimeType = file.mimeType
                    item.data = file.data
                    item.byteCount = file.data.count
                    item.phase = .pending
                    // A tile the user removed while it loaded stays removed.
                    if let index = localTray.firstIndex(where: { $0.id == item.id }) {
                        localTray[index] = item
                    }
                case .failure(.unopenable):
                    localTray.removeAll { $0.id == item.id }
                    localAttachmentError = "Couldn't open \(name)."
                case .failure(.unreadable):
                    localTray.removeAll { $0.id == item.id }
                    localAttachmentError = "Couldn't read \(name)."
                case .failure(.tooLarge):
                    localTray.removeAll { $0.id == item.id }
                    localAttachmentError = "\(name) is too large (50 MB max)."
                }
            }
            pumpLocalUploads()
        }
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
        // Every image on the pasteboard, not just the first (D2 §2).
        Task { attachPastedImages(await PasteImageLoader.loadAll()) }
    }

    /// Pasted images, in pasteboard order, through the same path a picked photo takes.
    private func attachPastedImages(_ images: [Data]) {
        guard !images.isEmpty else {
            localAttachmentError = "Failed to paste image"
            return
        }
        for data in images {
            attachImage(data, fileName: "pasted-\(UUID().uuidString.prefix(8)).jpg")
        }
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
        VoiceLog.log.info("lane: start requested for \(store.agentId, privacy: .public)")
        Task {
            let ok = await voice.start(agentId: store.agentId)
            VoiceLog.log.info("lane: start returned \(ok)")
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
            .padding(.bottom, 6)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: Expand and mascot

    /// The tall draft's expand control, in the card's top-trailing corner (H3 §2).
    ///
    /// It used to sit `.padding(.trailing, 104)` to the left — "the crab's spot" — although the
    /// crab's 72 pt frame stands *above* the card, so the control floated a crab's width from the
    /// corner it belongs to, over the first line of text, at whatever that literal happened to
    /// make on the current model. The `1` on its top edge was the same kind of guess.
    ///
    /// Now nothing is hard-coded except tokens: the 44 pt hit frame is flush with the card's
    /// corner (it hangs `verticalInset` up into the card's padding, see `fieldRow`) and its 28 pt
    /// circle lands `(hitSize − expandSize) / 2 = 8` pt inside, the same 8 pt the row's 36 pt
    /// circles keep (E1 §4). The field gives back exactly that column while the control is shown
    /// (`ComposerUITextView.applyTrailingInset`), so no glyph ever runs under it.
    ///
    /// It can never meet the crab: the crab's feet are on the card's top edge and its 104 × 72 pt
    /// frame is above it, while this control is inside the card — no width, type size, mode or
    /// mascot state brings them together, so the crab does not have to move.
    @ViewBuilder private var expandComposerButton: some View {
        if expandControlShown {
            Button {
                if controller != nil {
                    controller?.showFullScreenComposer = true
                } else {
                    showDraftFullScreen = true
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: ComposerMetrics.expandSize, height: ComposerMetrics.expandSize)
                    .background(Palette.chip, in: .circle)
                    .frame(width: ComposerMetrics.hitSize, height: ComposerMetrics.hitSize)
                    .contentShape(.rect)
            }
            .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
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
#endif
