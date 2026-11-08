#if canImport(UIKit)
    import SwiftUI
    import CoreText

    public struct ClaudeTypography: Sendable {
        public var serifName: String
        public init(serifName: String = "Newsreader16pt-Regular") { self.serifName = serifName }
    }
    enum ClaudePalette {
        static let background = Color(
            uiColor: UIColor {
                $0.userInterfaceStyle == .dark
                    ? UIColor(white: 20 / 255, alpha: 1) : UIColor(red: 0.976, green: 0.976, blue: 0.969, alpha: 1)
            })
        static let codeBackground = adaptive(light: 0.98, dark: 0.04)
        static let panel = adaptive(light: 1, dark: 0.13)
        static let composer = adaptive(light: 0.99, dark: 0.19)
        static let secondary = Color(white: 0.56)
        static let ink = adaptive(light: 0.13, dark: 0.93)
        static func adaptive(light: Double, dark: Double) -> Color {
            Color(
                uiColor: UIColor {
                    $0.userInterfaceStyle == .dark ? UIColor(white: dark, alpha: 1) : UIColor(white: light, alpha: 1)
                })
        }
        static let orange = Color(red: 0.80, green: 0.36, blue: 0.23)
    }
    enum ClaudeSheet: String, Identifiable {
        case attachments, models, settings, voice, voiceModels
        var id: String { rawValue }
    }

    /// Bind this screen to app-owned state and handle its intents in your own backend adapter.
    /// The package never starts network requests, microphone sessions, or automation.
    public struct ClaudeSessionView: View {
        @Binding var state: SessionState
        var typography: ClaudeTypography
        private var mediaContent: (ClaudeMedia, ClaudeMediaPresentation) -> AnyView
        private var settingsDestinationContent: ((ClaudeSettingsDestination) -> AnyView?)?
        var onAction: (ClaudeAction) -> Void
        @State private var sidebar = false
        @State private var sheet: ClaudeSheet?
        @State private var voiceStartedAt: Date?
        @State private var voiceEndedDuration: String?
        @State private var voiceToastTask: Task<Void, Never>?
        @State private var toast: String?
        @State private var toastTask: Task<Void, Never>?
        @State private var copiedResetTask: Task<Void, Never>?
        @State private var copied: UUID?
        @FocusState private var focused: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        public init(
            state: Binding<SessionState>, typography: ClaudeTypography = .init(),
            mediaContent: @escaping (ClaudeMedia, ClaudeMediaPresentation) -> AnyView = { _, _ in
                AnyView(ClaudeMediaPlaceholder())
            }, settingsDestinationContent: ((ClaudeSettingsDestination) -> AnyView?)? = nil,
            onAction: @escaping (ClaudeAction) -> Void
        ) {
            _state = state
            self.typography = typography
            self.mediaContent = mediaContent
            self.settingsDestinationContent = settingsDestinationContent
            self.onAction = onAction
            ClaudeFontResources.register()
        }
        private var surfaceBackground: Color {
            (state.showingProjects || (state.showingCode && !state.code.showingNewSession))
                ? ClaudePalette.codeBackground : ClaudePalette.background
        }
        public var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    surfaceBackground.ignoresSafeArea()
                    if sidebar { sidebarView(width: geometry.size.width * 0.82) }
                    Group {
                        if state.showingProjects {
                            ClaudeProjectsView(
                                state: $state.projects, typography: typography, openSidebar: toggleSidebar
                            ) { onAction(.projects($0)) }
                        } else if state.showingCode {
                            ClaudeCodeView(state: $state.code, openSidebar: toggleSidebar) { onAction(.code($0)) }
                        } else {
                            main
                        }
                    }
                    .background(surfaceBackground)
                    .clipShape(.rect(cornerRadius: sidebar ? 44 : 0))
                    .overlay { if sidebar { Color.black.opacity(0.45).onTapGesture { toggleSidebar() } } }
                    .offset(x: sidebar ? geometry.size.width * 0.82 : 0)
                    .shadow(color: .black.opacity(sidebar ? 0.25 : 0), radius: 8)
                }.clipped()
            }
            .background(surfaceBackground.ignoresSafeArea())
            .preferredColorScheme(state.appearance == .system ? nil : state.appearance == .dark ? .dark : .light)
            .tint(ClaudePalette.ink)
            .sheet(item: $sheet) { selection in
                switch selection {
                case .attachments: ClaudeAttachmentSheet(state: $state, mediaContent: mediaContent, action: onAction)
                case .models: ClaudeModelSheet(state: $state, action: onAction)
                case .settings:
                    ClaudeSettingsView(
                        state: $state.settings, appearance: state.appearance,
                        destinationContent: settingsDestinationContent
                    ) { onAction(.settings($0)) }
                case .voice: ClaudeVoiceSettingsSheet(state: $state, action: onAction)
                case .voiceModels: ClaudeModelSheet(state: $state, action: onAction, voiceContext: true)
                }
            }
            .fullScreenCover(
                item: Binding(
                    get: { state.media.viewer?.kind == .image ? state.media.viewer : nil },
                    set: { if $0 == nil { onAction(.media(.close)) } })
            ) { item in
                ClaudeMediaViewer(item: item, controlsVisible: state.media.controlsVisible, mediaContent: mediaContent)
                { onAction(.media($0)) }
            }
            .sheet(
                item: Binding(
                    get: { state.media.viewer?.kind == .video ? state.media.viewer : nil },
                    set: { if $0 == nil { onAction(.media(.close)) } })
            ) { item in
                ClaudeVideoFileViewer(item: item, mediaContent: mediaContent) { onAction(.media($0)) }
            }
            .onChange(of: state.voiceActive, initial: true) { _, active in
                if active {
                    voiceStartedAt = Date()
                    dismissVoiceToast()
                }
            }
            .overlay(alignment: .top) {
                if let voiceEndedDuration { voiceEndedToast(duration: voiceEndedDuration).padding(.horizontal, 12) }
            }
            .overlay(alignment: .top) {
                if let toast {
                    Text(toast).font(.subheadline).padding(.horizontal, 20).padding(.vertical, 10).glassEffect()
                        .padding(.top, 66).allowsHitTesting(false)
                }
            }
        }
        private var main: some View {
            VStack(spacing: 0) {
                header.padding(.horizontal, 16).padding(.top, -2)
                if state.messages.isEmpty {
                    GeometryReader { geo in
                        VStack(spacing: 16) {
                            Image("ClaudeLogo", bundle: .module).resizable().scaledToFit().frame(width: 36, height: 36)
                            Text("Evening, how are things?")
                                .font(.custom(typography.serifName, size: 25, relativeTo: .title)).foregroundStyle(
                                    ClaudePalette.adaptive(light: 0.24, dark: 0.76)
                                )
                                .multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).position(x: geo.size.width / 2, y: geo.size.height * 0.505)
                    }
                } else {
                    transcript
                }
                if state.voiceActive {
                    voiceControls.padding(.horizontal, 16)
                } else {
                    composer.padding(.horizontal, focused ? 8 : 16).padding(.bottom, 0)
                }
            }
        }
        private var header: some View {
            HStack {
                Button {
                    toggleSidebar()
                } label: {
                    UnequalMenu().stroke(
                        ClaudePalette.ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    ).frame(width: 18, height: 17).frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle).accessibilityLabel("Open sidebar").accessibilityIdentifier("sidebar.open")
                Spacer()
                if state.voiceActive {
                    Button {
                        sheet = .voice
                    } label: {
                        Image(systemName: "gearshape").font(.system(size: 20)).frame(width: 44, height: 44)
                    }.glassEffect(in: .circle).accessibilityLabel("Voice settings").accessibilityIdentifier(
                        "voice.settings")
                } else if !state.messages.isEmpty {
                    HStack(spacing: 0) {
                        Button {
                            onAction(.newSession)
                        } label: {
                            Image(systemName: "bubble.left.fill").overlay {
                                Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                            }.frame(width: 45, height: 44)
                        }.accessibilityLabel("New session")
                        Menu {
                            Button("Delete", systemImage: "trash", role: .destructive) { onAction(.newSession) }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 49, height: 44)
                        }.accessibilityLabel("Session options")
                    }.glassEffect(in: .capsule)
                }
            }.frame(height: 48)
        }
        private var transcript: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 27) {
                        ForEach(state.messages) { message in
                            if message.role == .user {
                                VStack(alignment: .trailing, spacing: 9) {
                                    ForEach(message.media) { item in
                                        Button {
                                            onAction(.media(.open(item)))
                                        } label: {
                                            if item.kind == .video {
                                                ClaudeVideoFileCard(item: item)
                                            } else {
                                                mediaContent(item, .message).frame(
                                                    width: min(194, 200 * item.displayAspectRatio),
                                                    height: min(200, 194 / item.displayAspectRatio)
                                                ).clipped().clipShape(.rect(cornerRadius: 14))
                                            }
                                        }.accessibilityLabel(item.accessibilityDescription).accessibilityIdentifier(
                                            "media.message." + item.id
                                        )
                                        .contextMenu {
                                            Button("Copy file name", systemImage: "document.on.document") {
                                                onAction(.media(.copyFileName(item)))
                                            }
                                        }
                                    }
                                    if !message.text.isEmpty {
                                        HStack {
                                            Spacer(minLength: 42)
                                            Text(message.text).font(.system(size: 18)).padding(.horizontal, 16).padding(
                                                .vertical, 14
                                            ).background(
                                                ClaudePalette.adaptive(light: 0.92, dark: 0.165),
                                                in: .rect(cornerRadius: 28))
                                        }.padding(.top, 6).contextMenu {
                                            Button("Copy", systemImage: "document.on.document") {
                                                onAction(.copy(message.id))
                                                showToast("Message copied")
                                            }
                                        }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                VStack(alignment: .leading, spacing: 18) {
                                    ClaudeMarkdownView(message.text, theme: .init(serifName: typography.serifName)) {
                                        onAction(.markdown(message.id, $0))
                                    }
                                    if state.phase != .streaming {
                                        HStack(spacing: 17) {
                                            if !state.voiceActive {
                                                responseButton(
                                                    copied == message.id ? "checkmark" : "square.on.square",
                                                    label: "Copy response"
                                                ) {
                                                    onAction(.copy(message.id))
                                                    copied = message.id
                                                    showToast("Message copied")
                                                    copiedResetTask?.cancel()
                                                    copiedResetTask = Task {
                                                        try? await Task.sleep(for: .seconds(2))
                                                        guard !Task.isCancelled else { return }
                                                        copied = nil
                                                    }
                                                }
                                            }
                                        }
                                        if !state.voiceActive {
                                            Text("Claude is AI and can make mistakes.").font(.system(size: 13))
                                                .foregroundStyle(ClaudePalette.secondary).padding(.top, 9)
                                        }
                                    }
                                }
                            }
                        }
                        if state.phase == .streaming {
                            Image("ClaudeLogo", bundle: .module).resizable().scaledToFit().frame(width: 22, height: 22)
                                .symbolEffect(.pulse)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 16).padding(.vertical, 20)
                }.scrollDismissesKeyboard(.interactively)
                    .onChange(of: state.messages.last?.text) {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
            }
        }
        private var composer: some View {
            VStack(alignment: .leading, spacing: 15) {
                if !state.media.draft.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(state.media.draft) { item in
                                Button {
                                    focused = false
                                    onAction(.media(.open(item)))
                                } label: {
                                    mediaContent(item, .thumbnail).frame(width: 80, height: 80).clipped().clipShape(
                                        .rect(cornerRadius: 16))
                                }
                                .accessibilityLabel(item.accessibilityDescription).accessibilityIdentifier(
                                    "media.draft." + item.id
                                )
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        onAction(.media(.removeDraft(item.id)))
                                    } label: {
                                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.black).frame(width: 24, height: 24).background(
                                                .white, in: .circle)
                                    }.accessibilityLabel("Remove " + item.fileName).accessibilityIdentifier(
                                        "media.remove." + item.id)
                                }
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                if !state.attachments.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(state.attachments, id: \.self) { name in
                                Button {
                                    onAction(.removeAttachment(name))
                                } label: {
                                    Label(name, systemImage: "doc").font(.caption).padding(8).background(
                                        ClaudePalette.adaptive(light: 0.94, dark: 0.24), in: .capsule
                                    ).overlay(alignment: .topTrailing) {
                                        Image(systemName: "xmark.circle.fill").font(.caption2)
                                    }
                                }.accessibilityLabel("Remove \(name)")
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                TextField(
                    "", text: $state.draft,
                    prompt: Text(state.messages.isEmpty ? "Chat with Claude" : "Reply to Claude").foregroundStyle(
                        ClaudePalette.secondary), axis: .vertical
                )
                .font(.system(size: 18)).lineLimit(1...16).fixedSize(horizontal: false, vertical: true).focused(
                    $focused
                ).tint(ClaudePalette.ink)
                .padding(.horizontal, 6).padding(.top, 7).disabled(
                    state.phase == .recording || state.phase == .recordingPaused
                )
                .accessibilityIdentifier("composer.draft")
                if state.phase == .recording || state.phase == .recordingPaused {
                    dictationControls
                } else {
                    HStack(spacing: 8) {
                        roundButton("plus", label: "Add to session") {
                            focused = false
                            sheet = .attachments
                        }.accessibilityIdentifier("composer.attach")
                        Button {
                            focused = false
                            sheet = .models
                        } label: {
                            HStack(spacing: 3) {
                                Text(state.model.rawValue)
                                Text(state.effort.rawValue).foregroundStyle(ClaudePalette.secondary)
                            }.font(.system(size: 14)).padding(.horizontal, 16).frame(height: 36).background(
                                ClaudePalette.adaptive(light: 0.94, dark: 0.24), in: .capsule)
                        }.accessibilityIdentifier("composer.model")
                        Spacer(minLength: 0)
                        roundButton("mic", label: "Dictate") {
                            focused = false
                            onAction(.startDictation)
                        }.disabled(state.phase == .streaming).accessibilityIdentifier("composer.dictate")
                        if state.phase == .streaming {
                            roundButton("stop.fill", label: "Stop response") { onAction(.stop) }
                                .accessibilityIdentifier("composer.stop")
                        } else if state.canSend {
                            roundButton("arrow.up", label: "Send message", color: ClaudePalette.orange, ink: .white) {
                                focused = false
                                onAction(.send(state.draft))
                            }.accessibilityIdentifier("composer.send")
                        } else {
                            roundButton(
                                "waveform", label: "Voice conversation",
                                color: ClaudePalette.adaptive(light: 0.08, dark: 0.94),
                                ink: ClaudePalette.adaptive(light: 1, dark: 0.08)
                            ) {
                                focused = false
                                onAction(.startVoice)
                            }.accessibilityIdentifier("composer.voice")
                        }
                    }
                }
            }.padding(8).padding(.top, 1)
                .background(ClaudePalette.composer, in: .rect(cornerRadius: 27))
                .overlay {
                    RoundedRectangle(cornerRadius: 27).stroke(
                        ClaudePalette.adaptive(light: 0.79, dark: 0.29), lineWidth: 0.7)
                }
        }
        private var voiceControls: some View {
            VStack(spacing: 21) {
                Button {
                    onAction(.toggleVoiceInput)
                } label: {
                    Image(systemName: state.voiceInputEnabled ? "mic" : "mic.slash").font(
                        .system(size: 30, weight: .light)
                    ).frame(width: 64, height: 64)
                }.glassEffect(in: .circle).accessibilityLabel("Voice microphone").accessibilityValue(
                    state.voiceInputEnabled ? "On" : "Off"
                ).accessibilityIdentifier("voice.microphone")
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            sheet = .attachments
                        } label: {
                            Image(systemName: "plus").font(.system(size: 23, weight: .light)).frame(
                                width: 44, height: 44)
                        }.glassEffect(in: .circle).accessibilityLabel("Add to session")
                        Button {
                            sheet = .voiceModels
                        } label: {
                            HStack(spacing: 12) {
                                Text(state.model.rawValue.components(separatedBy: " ")[0]).font(.system(size: 14))
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 14, weight: .light))
                            }.padding(.horizontal, 16).frame(height: 44)
                        }.glassEffect(in: .capsule).accessibilityLabel("Voice model").accessibilityIdentifier(
                            "voice.model")
                        Spacer(minLength: 0)
                        Button {
                            onAction(.toggleVoiceOutput)
                        } label: {
                            Image(systemName: state.voiceOutputMuted ? "speaker.slash" : "speaker.wave.2").font(
                                .system(size: 20, weight: .light)
                            ).frame(width: 44, height: 44)
                        }.glassEffect(in: .circle).accessibilityLabel("Voice output").accessibilityValue(
                            state.voiceOutputMuted ? "Muted" : "On"
                        ).accessibilityIdentifier("voice.output")
                        Button {
                            endVoice()
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 21, weight: .light)).foregroundStyle(.black)
                                .frame(width: 44, height: 44).background(.white, in: .circle)
                        }.accessibilityLabel("Exit voice").accessibilityIdentifier("voice.exit")
                    }
                }
            }
        }
        private var dictationControls: some View {
            HStack(spacing: 10) {
                roundButton("xmark", label: "Cancel dictation") { onAction(.cancelDictation) }.accessibilityIdentifier(
                    "dictation.cancel")
                GeometryReader { geo in
                    let heights = DictationWaveformMetrics.barHeights(
                        for: state.dictationLevels, count: Int(geo.size.width / DictationWaveformMetrics.sampleSpacing))
                    ZStack(alignment: .topLeading) {
                        ForEach(heights.indices, id: \.self) { index in
                            Capsule().fill(ClaudePalette.ink.opacity(0.65))
                                .frame(width: DictationWaveformMetrics.dotDiameter, height: heights[index])
                                .position(
                                    x: CGFloat(index) * DictationWaveformMetrics.sampleSpacing + 4.3,
                                    y: geo.size.height / 2)
                        }
                    }.animation(reduceMotion ? nil : .linear(duration: 0.08), value: state.dictationLevels)
                }.frame(height: 36).clipped().accessibilityLabel(
                    state.phase == .recording ? "Listening" : "Recording paused"
                ).accessibilityIdentifier("dictation.waveform")
                if state.phase == .recording {
                    roundButton("stop.fill", label: "Stop dictation") { onAction(.stopDictation) }
                        .accessibilityIdentifier("dictation.stop")
                }
                roundButton("arrow.up", label: "Use dictation", color: ClaudePalette.orange, ink: .white) {
                    onAction(.commitDictation)
                }.accessibilityIdentifier("dictation.commit")
            }
        }
        private func roundButton(
            _ symbol: String, label: String, color: Color = ClaudePalette.adaptive(light: 0.94, dark: 0.24),
            ink: Color = ClaudePalette.ink, action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Group {
                    if symbol == "waveform", label == "Voice conversation" {
                        HStack(spacing: 2.1) {
                            ForEach(Array([4.5, 9.5, 16.5, 9.5, 14, 4.5].enumerated()), id: \.offset) { _, height in
                                Capsule().frame(width: 1.5, height: height)
                            }
                        }
                    } else {
                        Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                    }
                }.frame(width: 36, height: 36).foregroundStyle(ink).background(color, in: .circle)
            }.accessibilityLabel(label)
        }
        private func responseButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: symbol).font(.system(size: 18, weight: .light)).foregroundStyle(
                    ClaudePalette.secondary)
            }.accessibilityLabel(label)
        }
        private func toggleSidebar() {
            focused = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.88)) { sidebar.toggle() }
        }
        private func endVoice() {
            let seconds = max(0, Int(Date().timeIntervalSince(voiceStartedAt ?? Date())))
            voiceEndedDuration = seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
            voiceStartedAt = nil
            onAction(.endVoice)
            voiceToastTask?.cancel()
            // The banner was observed for several seconds; exact dismissal timing remains unmeasured.
            voiceToastTask = Task {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                voiceEndedDuration = nil
            }
        }
        private func dismissVoiceToast() {
            voiceToastTask?.cancel()
            voiceEndedDuration = nil
        }
        private func voiceEndedToast(duration: String) -> some View {
            HStack(spacing: 12) {
                Image(systemName: "waveform").font(.system(size: 20, weight: .light)).foregroundStyle(
                    ClaudePalette.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Voice chat ended").font(.system(size: 14, weight: .medium))
                    Text(duration).font(.system(size: 13))
                }
                Spacer(minLength: 0)
                Button {
                    dismissVoiceToast()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 20, weight: .light)).frame(width: 32, height: 44)
                        .contentShape(.rect)
                }.accessibilityLabel("Dismiss voice summary").accessibilityIdentifier("voice.summary.dismiss")
            }.buttonStyle(.plain).foregroundStyle(ClaudePalette.ink).padding(.horizontal, 12).frame(height: 62)
                .glassEffect(in: .rect(cornerRadius: 17))
        }
        private func showToast(_ text: String) {
            toastTask?.cancel()
            toast = text
            toastTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                toast = nil
            }
        }
        private func openDestination(_ name: String) {
            if name == "Projects" {
                onAction(.openProjects)
                if sidebar { toggleSidebar() }
            } else if name == "Code" {
                onAction(.openCode)
                if sidebar { toggleSidebar() }
            }
        }
        private func sidebarView(width: CGFloat) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Claude").font(.custom(typography.serifName, size: 27))
                    Spacer()
                }.padding(.horizontal, 16).frame(height: 48)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(
                            [
                                ("Projects", "rectangle.stack"), ("Code", "chevron.left.forwardslash.chevron.right"),
                                ("Scheduled", "clock"),
                            ], id: \.0
                        ) { label, symbol in
                            Button {
                                openDestination(label)
                            } label: {
                                Label(label, systemImage: symbol).font(.system(size: 18)).frame(
                                    maxWidth: .infinity, alignment: .leading
                                ).frame(height: 50)
                            }
                        }
                        Text("Pinned").font(.system(size: 15)).foregroundStyle(ClaudePalette.secondary).padding(
                            .vertical, 16)
                        ForEach(
                            [
                                "Weekend reading list", "Design exploration", "A small garden", "Learning Swift",
                                "Travel ideas"
                            ], id: \.self
                        ) { name in sessionRow(name) }
                        Button("Show all 5 ⌄") { openDestination("Pinned sessions") }.font(.system(size: 14))
                            .foregroundStyle(ClaudePalette.secondary).padding(.vertical, 15)
                        Text("Recents").font(.system(size: 15)).foregroundStyle(ClaudePalette.secondary).padding(
                            .vertical, 16)
                        ForEach(["Planning a new project", "Thoughts on typography", "A short greeting"], id: \.self) {
                            name in sessionRow(name)
                        }
                    }.padding(.horizontal, 24)
                }.scrollIndicators(.hidden)
                HStack {
                    Button {
                        sheet = .settings
                    } label: {
                        Image(systemName: "gearshape").font(.system(size: 18)).frame(width: 48, height: 48)
                    }.glassEffect(in: .circle).accessibilityLabel("Settings").accessibilityIdentifier(
                        "sidebar.settings")
                    Spacer()
                    Button {
                        onAction(.newSession)
                        toggleSidebar()
                    } label: {
                        Label("New session", systemImage: "plus").font(.system(size: 16)).foregroundStyle(.black)
                            .padding(.horizontal, 17).frame(height: 48).background(.white, in: .capsule)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 4)
            }.frame(width: width).background(ClaudePalette.adaptive(light: 0.96, dark: 0.065))
        }
        private func sessionRow(_ name: String) -> some View {
            Button {
                onAction(.newSession)
                toggleSidebar()
            } label: {
                Label(name, systemImage: "bubble.left").font(.system(size: 18)).lineLimit(1).frame(
                    maxWidth: .infinity, alignment: .leading
                ).frame(height: 50)
            }
        }
    }
    struct UnequalMenu: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                for (y, width) in [(0.1, 1.0), (0.5, 1.0), (0.9, 0.5)] {
                    p.move(to: CGPoint(x: 0, y: rect.height * y))
                    p.addLine(to: CGPoint(x: rect.width * width, y: rect.height * y))
                }
            }
        }
    }
#endif
