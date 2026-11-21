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
    /// uploads through the session's channel before the create request. Its loading, upload pump
    /// and stash for a failed create live in `DraftAttachmentTray`, not here.
    @State private var draftTray = DraftAttachmentTray()
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
    @State private var viewedImage: ViewedAttachmentImage?
    @State private var surfaceHeight: CGFloat = 0
    /// Whether the tall draft's expand control is in the card's corner, and with it whether the
    /// field reserves the corner's trailing column. **Written by the field** from its own laid-out
    /// line count, only when the answer flips: sticky between `ComposerMetrics.expandShowLines`
    /// and `expandHideLines` (H3 §2), so a word wrapping at the threshold cannot flicker the
    /// control and re-flow the text on consecutive keystrokes.
    @State private var expandVisible = false

    @Environment(\.composerFocusRequested) private var composerFocusRequested
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
                if controller.isQueueNonEmpty {
                    ComposerQueueStack(controller: controller, focused: $focused)
                        .transition(
                            reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                }
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
            guard error != nil else { return }
            draftTray.restoreStash()
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
        controller?.trayItems ?? draftTray.items
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
        return draftTray.error ?? draftSession?.error
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
                DictationOverlay(
                    dictation: dictation,
                    onCancel: { dictation.cancel() },
                    onAccept: { dictation.stop(keepingDraft: true) },
                    onAcceptAndSend: {
                        dictation.stop(keepingDraft: true)
                        send()
                    })
            } else {
                if composerExpanded, !trayItems.isEmpty {
                    ComposerAttachmentTray(
                        items: trayItems,
                        uploads: store?.uploads ?? draftHost?.fileUploader,
                        onRemove: removeAttachment,
                        onRetry: retryAttachment,
                        onTapImage: { image in viewedImage = ViewedAttachmentImage(image: image) })
                }
                if composerExpanded, activeDictation?.isDenied == true {
                    ComposerDictationDeniedBanner()
                }
                if composerExpanded, let failure = activeDictation?.failure {
                    ComposerDictationFailureBanner(failure: failure, onRetry: retryDictation)
                }
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
            viewedImage: $viewedImage,
            forgeIsGitLab: forgeIsGitLab,
            onFileURLs: attachFileURLs,
            onFileImportError: reportAttachmentError,
            onCameraImage: attachCameraImage,
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
            ComposerExpandButton(isShown: expandControlShown, action: expandComposer)
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

    /// The failure banner's retry: clears the note and starts again.
    private func retryDictation() {
        activeDictation?.dismissFailure()
        if let dictation = activeDictation {
            dictation.toggle(currentDraft: text)
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
        ComposerAddMenu(
            photoSelection: $photoSelection,
            showCameraPicker: $showCameraPicker,
            showFileImporter: $showFileImporter,
            cameraAvailable: cameraAvailable,
            forgeIsGitLab: forgeIsGitLab,
            onPasteImage: pasteImageFromClipboard,
            onAddForge: openForgePicker,
            onMentionFile: mentionFile,
            onNewAgent: { controller?.newAgent(draft: text) },
            onCopyAgentId: { controller?.copyAgentId() })
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
            ComposerFastModeChip {
                Task { await store?.setFeatureToggle(featureId: "fast_mode", value: false) }
            }
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
            draftTray.error = nil
            draft.clearError()
            Haptics.send()
            // The tray leaves the field before the hop, with a copy kept for a failed create:
            // once the shell swaps the conversation in, this view's state is never written again
            // (D2 §3). The shell runs the create from a task it owns.
            let submission = DraftSubmission(text: draft.text, attachments: readyAttachments)
            draftTray.stashForSubmission()
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

    private func attachFileURLs(_ urls: [URL]) {
        if let controller {
            controller.attachFileURLs(urls)
            return
        }
        guard let session = draftHost else { return }
        draftTray.addFiles(urls, session: session)
    }

    private func handlePickedPhotos(_ selection: [PhotosPickerItem]) {
        Task {
            var failed = 0
            for picked in selection {
                guard let data = try? await picked.loadTransferable(type: Data.self) else {
                    failed += 1
                    continue
                }
                attachImage(data, fileName: "photo-\(UUID().uuidString.prefix(8)).jpg")
            }
            photoSelection = []
            // A photo that would not load (an iCloud photo offline, an unsupported asset) is said
            // so, as the file and paste paths say theirs.
            guard failed > 0 else { return }
            reportAttachmentError(
                failed == 1 ? "Couldn't load that photo." : "Couldn't load \(failed) photos.")
        }
    }

    /// A camera frame: encoded off the main actor (a full-resolution frame is tens to hundreds of
    /// milliseconds of JPEG work), then through the same path as a picked photo.
    private func attachCameraImage(_ image: UIImage) {
        Task {
            guard let data = await ComposerImageProcessor.jpegData(of: image) else {
                reportAttachmentError("Couldn't read that photo.")
                return
            }
            attachImage(data, fileName: "photo-\(UUID().uuidString.prefix(8)).jpg")
        }
    }

    /// A failed pick, said where this mode says its errors: a toast in a conversation, the line
    /// under the field in a draft.
    private func reportAttachmentError(_ message: String) {
        if let controller {
            controller.showToast(message)
        } else {
            draftTray.error = message
        }
    }

    /// A picked or pasted image: the conversation hands it to its controller (which decodes off
    /// main into the shared tray); a draft shows the `.decoding` tile and does the same in its
    /// own tray.
    private func attachImage(_ data: Data, fileName: String) {
        if let controller {
            controller.attachImageData(data, fileName: fileName)
            return
        }
        guard let session = draftHost else { return }
        draftTray.addImage(data, fileName: fileName, session: session)
    }

    private func removeAttachment(_ id: UUID) {
        if let controller {
            controller.removeAttachment(id)
            return
        }
        draftTray.remove(id)
    }

    private func retryAttachment(_ id: UUID) {
        if let controller {
            controller.retryAttachment(id)
            return
        }
        guard let session = draftHost else { return }
        draftTray.retry(id, session: session)
    }

    private func pasteImageFromClipboard() {
        // Every image on the pasteboard, not just the first (D2 §2).
        Task { attachPastedImages(await PasteImageLoader.loadAll()) }
    }

    /// Pasted images, in pasteboard order, through the same path a picked photo takes.
    private func attachPastedImages(_ images: [Data]) {
        guard !images.isEmpty else {
            reportAttachmentError("Failed to paste image")
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

    // MARK: Expand and mascot

    /// The tall draft's expand control (`ComposerExpandButton`).
    private func expandComposer() {
        if controller != nil {
            controller?.showFullScreenComposer = true
        } else {
            showDraftFullScreen = true
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
