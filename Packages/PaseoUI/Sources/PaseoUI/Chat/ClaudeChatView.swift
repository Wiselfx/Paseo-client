#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One agent's conversation, rendered from `ConversationStore.turns` in ClaudeUI's clothes.
///
/// Layout follows `docs/research/06-dsh-ux-spec.md` §1 (turn structure, the counted work group,
/// the 36 pt process rows) and §2 (the live status line), on top of the M2 seam in
/// `docs/research/07-claudeui-adoption-map.md` §5.4. No networking here: everything is store state
/// and store calls.
public struct ClaudeChatView: View {
    let session: HostSession
    @Bindable var store: ConversationStore

    /// The drawer affordance in the shell. Nil keeps the leading edge empty.
    var onOpenSidebar: (() -> Void)?
    /// Selects another agent in the same workspace from the header's tab chips.
    var onSelectAgent: ((String) -> Void)?
    /// Back affordance for a plain navigation stack.
    var onBack: (() -> Void)?
    /// Called with the composer's text so a new agent can start with it.
    var onNewAgent: ((String) -> Void)?

    private let typography = ClaudeTypography()

    @State private var sheet: ClaudeChatSheet?
    @State private var toast: String?
    @FocusState private var focused: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        session: HostSession, store: ConversationStore, onOpenSidebar: (() -> Void)? = nil,
        onSelectAgent: ((String) -> Void)? = nil, onBack: (() -> Void)? = nil,
        onNewAgent: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.store = store
        self.onOpenSidebar = onOpenSidebar
        self.onSelectAgent = onSelectAgent
        self.onBack = onBack
        self.onNewAgent = onNewAgent
        ClaudeFontResources.register()
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            agentTabs
            if let banner = connectionBanner {
                banner.padding(.horizontal, 16).padding(.bottom, 6)
            }
            content
            composer
        }
        .background(ClaudePalette.background.ignoresSafeArea())
        .foregroundStyle(ClaudePalette.ink)
        .tint(ClaudePalette.ink)
        .sheet(item: $sheet) { _ in
            ClaudeAgentControlsSheet(session: session, store: store)
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(typography.sans(13))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect()
                    .padding(.top, 58)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: store.lastNotice?.message) { _, message in
            guard let message else { return }
            showToast(message)
            store.clearNotice()
        }
        .onChange(of: store.isRunning) { wasRunning, isRunning in
            if wasRunning && !isRunning { Haptics.settle() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if let onOpenSidebar {
                Button(action: onOpenSidebar) {
                    UnequalMenu().stroke(
                        ClaudePalette.ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                    .frame(width: 18, height: 17)
                    .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Open sidebar")
            } else if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Back")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(store.agent?.title ?? "Agent")
                    .font(typography.serif(20, relativeTo: .headline))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let onNewAgent {
                HStack(spacing: 0) {
                    Button { newAgent(draft: store.draft) } label: {
                        Image(systemName: "bubble.left.fill")
                            .overlay {
                                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                            .frame(width: 45, height: 44)
                    }
                    .accessibilityLabel("New agent")
                    Menu {
                        Button("Archive agent", systemImage: "archivebox", role: .destructive) {
                            Task { await store.archive() }
                        }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 49, height: 44)
                    }
                    .accessibilityLabel("Agent options")
                }
                .glassEffect(in: .capsule)
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let agent = store.agent {
            parts.append(providerLabel(agent.provider) ?? agent.provider)
            if let model = modelLabel { parts.append(model) }
            if let mode = modeLabel { parts.append(mode) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func providerLabel(_ id: String) -> String? {
        session.agentControl.provider(id)?.label
    }

    private var modelLabel: String? {
        guard let agent = store.agent else { return nil }
        if let id = agent.model,
            let match = session.agentControl.models(forProvider: agent.provider).first(where: { $0.id == id })
        {
            return match.label
        }
        return session.agentControl.defaultModel(forProvider: agent.provider)?.label ?? agent.model
    }

    private var modeLabel: String? {
        guard let id = store.agent?.currentModeId else { return nil }
        return store.agent?.availableModes.first(where: { $0.id == id })?.label
    }

    private func newAgent(draft: String) {
        focused = false
        onNewAgent?(draft)
    }

    /// The workspace's agents as tab chips, the way Paseo keeps them together.
    @ViewBuilder private var agentTabs: some View {
        if let onSelectAgent, workspaceAgents.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(workspaceAgents) { agent in
                        let selected = agent.id == store.agentId
                        Button {
                            Haptics.selection()
                            onSelectAgent(agent.id)
                        } label: {
                            HStack(spacing: 6) {
                                if agent.requiresAttention == true && !selected {
                                    Circle().fill(ClaudePalette.warning).frame(width: 6, height: 6)
                                }
                                Text(agent.title ?? "New agent")
                                    .font(typography.sans(14, weight: selected ? .medium : .regular))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .foregroundStyle(selected ? ClaudePalette.background : ClaudePalette.ink)
                            .background(
                                selected ? ClaudePalette.ink : ClaudePalette.chip, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(agent.title ?? "New agent")
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, 6)
        }
    }

    private var workspaceAgents: [AgentSnapshot] {
        guard let agent = store.agent else { return [] }
        guard let workspaceId = agent.workspaceId else { return [agent] }
        var siblings = session.agents.filter { $0.workspaceId == workspaceId }
        // A just-created agent can be live here before the refreshed list arrives.
        if !siblings.contains(where: { $0.id == agent.id }) { siblings.insert(agent, at: 0) }
        return siblings
    }

    // MARK: Connection

    private var connectionBanner: AnyView? {
        switch session.connection {
        case .reconnecting(let attempt, _):
            return AnyView(
                bannerRow("Reconnecting to host", detail: "Attempt \(attempt)"))
        case .failed:
            return AnyView(bannerRow("Disconnected", detail: nil))
        case .idle, .connecting, .connected:
            return nil
        }
    }

    private func bannerRow(_ title: String, detail: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 13))
            Text(title).font(typography.sans(13, weight: .medium))
            if let detail {
                Text(detail).font(typography.sans(13)).foregroundStyle(ClaudePalette.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(ClaudePalette.secondaryInk)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(ClaudePalette.adaptive(light: 0.95, dark: 0.18), in: .rect(cornerRadius: 10))
    }

    // MARK: Transcript

    @ViewBuilder private var content: some View {
        if store.turns.isEmpty, store.pendingPermissions.isEmpty {
            switch store.phase {
            case .loading:
                Spacer()
                ProgressView()
                Spacer()
            case .failed(let message):
                emptyState(title: "Couldn't load agent history", detail: message)
            case .ready:
                ClaudeHomeHero(hint: nil)
            }
        } else {
            transcript
        }
    }

    private func emptyState(title: String, detail: String?) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(typography.serif(25, relativeTo: .title))
                .foregroundStyle(ClaudePalette.ink)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(typography.sans(14))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcript: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 27) {
                        if store.timeline.hasOlder { olderHistoryRow }
                        ForEach(store.turns) { turn in
                            ClaudeTurnView(
                                turn: turn, typography: typography,
                                onMarkdown: handleMarkdown
                            )
                            .id(turn.id)
                        }
                        if !store.pendingPermissions.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(store.pendingPermissions) { request in
                                    ClaudePermissionCard(request: request, store: store)
                                }
                            }
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.22),
                                value: store.pendingPermissions.count)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                // Follows the tail as it streams; loading older pages at the top does not jump.
                .onChange(of: store.turns.last) { _, _ in scrollToBottom(proxy) }
                .onChange(of: store.pendingPermissions) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { scrollToBottom(proxy) }
                }
                .onChange(of: focused) { _, isFocused in
                    if isFocused { scrollToBottom(proxy) }
                }
                .environment(\.claudeProcessCap, min(400, geometry.size.height * 0.5))
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private var olderHistoryRow: some View {
        Group {
            if store.isLoadingOlder {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else {
                Button {
                    Task { await store.loadOlder() }
                } label: {
                    Text("Load earlier")
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 30)
        // Reaching the top fetches one older page; the row stays put so it does not loop.
        .onAppear { Task { await store.loadOlder() } }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.actionError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
            TextField(
                "", text: $store.draft,
                prompt: Text(store.turns.isEmpty ? "Chat with Paseo" : "Reply to Paseo")
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
                Spacer(minLength: 0)
                roundButton("mic", label: "Dictate", color: ClaudePalette.chip, ink: ClaudePalette.ink) {
                    focused = true
                }
                .accessibilityIdentifier("composer.dictate")
                if store.isRunning && trimmedDraft.isEmpty {
                    roundButton("stop.fill", label: "Stop response", color: ClaudePalette.ink, ink: ClaudePalette.background) {
                        Task { await store.cancel() }
                    }
                    .accessibilityIdentifier("composer.stop")
                } else {
                    roundButton(
                        "arrow.up", label: store.isRunning ? "Send and steer" : "Send message",
                        color: ClaudePalette.orange, ink: .white
                    ) {
                        send()
                    }
                    .disabled(trimmedDraft.isEmpty)
                    .opacity(trimmedDraft.isEmpty ? 0.4 : 1)
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
        .padding(.horizontal, focused ? 8 : 16)
        .animation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.feedback), value: focused)
    }

    private var trimmedDraft: String {
        store.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var modelChipTitle: String {
        modelLabel ?? "Model"
    }

    private var thinkingLabel: String? {
        guard let agent = store.agent, let model = agent.effectiveThinkingOptionId ?? agent.thinkingOptionId else {
            return nil
        }
        guard let modelId = agent.model else { return nil }
        return session.agentControl.thinkingOptions(forProvider: agent.provider, modelId: modelId)
            .first(where: { $0.id == model })?.label
    }

    private func send() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        focused = false
        Haptics.send()
        Task { await store.send(text) }
    }

    private func roundButton(
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

    private func handleMarkdown(_ action: MarkdownAction) {
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

    private func showToast(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = nil }
        }
    }
}

enum ClaudeChatSheet: String, Identifiable {
    case controls
    var id: String { rawValue }
}

/// One turn: your bubble, the process header, the process body, the answer.
struct ClaudeTurnView: View {
    let turn: Turn
    let typography: ClaudeTypography
    let onMarkdown: (MarkdownAction) -> Void

    /// Nil until the reader taps, so the default can follow the turn's phase.
    @State private var userExpanded: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRunning: Bool { turn.phase == .running }
    private var isExpanded: Bool { userExpanded ?? isRunning }

    /// The answer stays visible even when the turn folds.
    private var finalProse: TimelineRow? {
        guard !isRunning, case .prose(let row)? = turn.segments.last else { return nil }
        return row
    }

    private var bodySegments: [Turn.Segment] {
        finalProse == nil ? turn.segments : Array(turn.segments.dropLast())
    }

    private var showsHeader: Bool { isRunning || !bodySegments.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let row = turn.userMessage, case .userMessage(let message) = row.item {
                ClaudeUserBubble(text: message.text, isPending: row.isPending)
            }
            if showsHeader { header }
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(bodySegments) { segment in
                        ClaudeSegmentView(
                            segment: segment, turnIsRunning: isRunning, typography: typography,
                            onMarkdown: onMarkdown)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -2)))
            }
            if let finalProse, case .assistantMessage(let message) = finalProse.item {
                ClaudeProse(markdown: message.text, typography: typography, onAction: onMarkdown)
            }
            if !isRunning, !copyText.isEmpty {
                HStack(spacing: 17) {
                    ClaudeCopyButton(text: copyText, label: "Copy response")
                }
                .padding(.top, 2)
            }
        }
        .onChange(of: turn.phase) { _, phase in
            // A finished turn folds itself away; the answer stays on the page.
            if phase != .running {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { userExpanded = nil }
            }
        }
    }

    private var copyText: String {
        var parts: [String] = []
        for segment in turn.segments {
            if case .prose(let row) = segment, case .assistantMessage(let message) = row.item {
                parts.append(message.text)
            }
        }
        return parts.joined(separator: "\n\n")
    }

    private var header: some View {
        Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
                userExpanded = !isExpanded
            }
        } label: {
            HStack(spacing: 8) {
                switch turn.phase {
                case .running:
                    ClaudeLiveStatusLine(turn: turn, typography: typography)
                case .completed:
                    Text(turn.duration.map(DurationText.completed) ?? "Completed")
                        .font(typography.sans(14))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    Spacer(minLength: 0)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(typography.sans(14))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                ClaudeChevron(expanded: isExpanded)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(isExpanded ? "Collapses the work in this turn" : "Shows the work in this turn")
    }
}

/// A segment of a turn.
struct ClaudeSegmentView: View {
    let segment: Turn.Segment
    let turnIsRunning: Bool
    let typography: ClaudeTypography
    let onMarkdown: (MarkdownAction) -> Void

    var body: some View {
        switch segment {
        case .work(let group):
            ClaudeWorkGroupCell(group: group, turnIsRunning: turnIsRunning, typography: typography)
        case .prose(let row):
            if case .assistantMessage(let message) = row.item {
                ClaudeProse(markdown: message.text, typography: typography, onAction: onMarkdown)
            }
        case .todo(let row):
            if case .todo(let list) = row.item { ClaudeTodoCard(list: list) }
        case .notice(let row):
            ClaudeNoticeRow(item: row.item)
        }
    }
}

/// "2 thoughts, 1 tool call": the counted header, then a transparent card of rows, each opening on
/// its own. The card is capped at `min(400 pt, 50% of height)` and scrolls inside.
struct ClaudeWorkGroupCell: View {
    let group: Turn.WorkGroup
    let turnIsRunning: Bool
    let typography: ClaudeTypography

    @State private var userExpanded: Bool?
    @State private var contentHeight: CGFloat = 0
    @State private var sweepStart = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.claudeProcessCap) private var processCap

    private var opensByDefault: Bool { turnIsRunning && group.isActive }
    private var isExpanded: Bool { userExpanded ?? opensByDefault }

    /// The leading seat's activity icon (doc 08 §1.2): the group's content decides the glyph.
    private var seatGlyph: ClaudeGlyph.Kind {
        var hasShell = false
        var hasFile = false
        for row in group.rows {
            if case .toolCall(let call) = row.item {
                switch call.detail {
                case .read, .edit, .write, .search, .fetch:
                    hasFile = true
                default:
                    hasShell = true
                }
            }
        }
        if hasShell { return .api }
        if hasFile { return .browse }
        return .think
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
                    userExpanded = !isExpanded
                }
            } label: {
                HStack(spacing: 6) {
                    ClaudeLeadingSeat(glyph: seatGlyph, expanded: isExpanded)
                    summary
                    Spacer(minLength: 4)
                }
                .frame(minHeight: 17.5) // the counted line: 14 pt × 1.25
                .contentShape(.rect)
            }
            .buttonStyle(ClaudePressButtonStyle())
            .accessibilityLabel(group.summary)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                card
                    .transition(.opacity.combined(with: .offset(y: -2)))
            }
        }
    }

    private func summaryRuns(_ ink: Color) -> some View {
        HStack(spacing: 3) {
            if group.thoughtCount > 0 {
                ClaudeRollingNumber(value: group.thoughtCount)
                Text(group.thoughtCount == 1 ? "thought" : "thoughts").tracking(-0.14)
            }
            if group.thoughtCount > 0 && group.toolCallCount > 0 {
                Text(",").tracking(-0.14)
            }
            if group.toolCallCount > 0 {
                ClaudeRollingNumber(value: group.toolCallCount)
                Text(group.toolCallCount == 1 ? "tool call" : "tool calls").tracking(-0.14)
            }
        }
        .font(typography.serif(14, weight: .medium))
        .foregroundStyle(ink)
    }

    private var summary: some View {
        Group {
            if turnIsRunning && group.isActive && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    summaryRuns(ClaudePalette.tertiaryInk).overlay(alignment: .leading) {
                        if let phase = ClaudeSweep.phase(startedAt: sweepStart, at: context.date) {
                            summaryRuns(ClaudePalette.shimmerInk)
                                .mask(ClaudeSweep.windowGradient(phase: phase))
                                .allowsHitTesting(false)
                        }
                    }
                }
            } else {
                summaryRuns(ClaudePalette.tertiaryInk)
            }
        }
    }

    private var card: some View {
        ScrollView(.vertical) {
            rows
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ClaudeGroupHeightKey.self, value: proxy.size.height)
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        // Hugs its rows until they reach the host's cap, then scrolls inside the card.
        .frame(height: min(max(contentHeight, 1), processCap), alignment: .top)
        .onPreferenceChange(ClaudeGroupHeightKey.self) { height in contentHeight = height }
        // The process card is transparent — the canvas shows through.
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Color.clear.frame(height: 4) // the gap above the hairline
                    ClaudeDivider()
                }
                ClaudeStepRow(
                    row: row, isLive: turnIsRunning && index == group.rows.count - 1,
                    typography: typography)
            }
        }
    }
}

private struct ClaudeGroupHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// One thought or tool call inside the process card: one line — 36 pt for thought and file rows,
/// 24 pt for shell/tool rows — a trailing chevron on the disclosure rows, detail below when open.
struct ClaudeStepRow: View {
    let row: TimelineRow
    /// The newest step of a running turn opens by default so you can watch it.
    let isLive: Bool
    let typography: ClaudeTypography

    @State private var userExpanded: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum RowKind { case thought, file, tool }

    private var kind: RowKind {
        switch row.item {
        case .reasoning: return .thought
        case .toolCall(let call):
            switch call.detail {
            case .read, .edit, .write: return .file
            default: return .tool
            }
        default: return .tool
        }
    }

    private var isExpanded: Bool { userExpanded ?? isLive }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
                    userExpanded = !isExpanded
                }
            } label: {
                HStack(spacing: 6) {
                    label
                    Spacer(minLength: 4)
                    if kind != .tool {
                        ClaudeTurnChevron(expanded: isExpanded)
                    }
                }
                .frame(minHeight: kind == .tool ? 24 : 36)
                .padding(.horizontal, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if isExpanded {
                detail
                    .transition(.opacity.combined(with: .offset(y: -2)))
            }
        }
    }

    @ViewBuilder private var label: some View {
        switch row.item {
        case .reasoning(let reasoning):
            if isExpanded {
                Text("Think")
                    .font(typography.serif(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            } else {
                Text(reasoning.text.replacingOccurrences(of: "\n", with: " "))
                    .font(typography.sans(13))
                    .lineSpacing(7) // 13 / 20
                    .foregroundStyle(ClaudePalette.tertiaryInk)
                    .lineLimit(1)
            }
        case .toolCall(let call):
            let presentation = ToolCallPresentation(call)
            if kind == .file {
                HStack(spacing: 0) {
                    Text(presentation.title)
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    if let subtitle = presentation.subtitle {
                        Circle().fill(ClaudePalette.captionInk).frame(width: 2, height: 2)
                            .padding(.horizontal, 8)
                        Text(subtitle)
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .underline(true, pattern: .dot, color: ClaudePalette.tertiaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ClaudeToolSeat(call: call, symbol: presentation.symbol)
                    Text(presentation.title)
                        .font(typography.serif(13, weight: .medium))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                    if let subtitle = presentation.subtitle {
                        Circle().fill(ClaudePalette.captionInk).frame(width: 2, height: 2)
                        Text(subtitle)
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var detail: some View {
        switch row.item {
        case .reasoning(let reasoning):
            // The opened thought scrolls with the group and holds no scrollbar of its own.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(reasoningParagraphs(reasoning.text), id: \.self) { paragraph in
                    Text(paragraph)
                        .font(typography.serif(13))
                        .lineSpacing(10) // 13 / 23
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)
            .padding(.leading, 22)
            .padding(.trailing, 12)
            .padding(.bottom, 10)
        case .toolCall(let call):
            ClaudeToolCallDetail(call: call)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        default:
            EmptyView()
        }
    }

    private func reasoningParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// The leading seat a shell/tool row keeps (doc 08 §1.3(d)): the tool's glyph — the `>-` prompt
/// for a shell call — inside a 16 × 16 box, swapped for a chevron on hover on DSH. Touch has no
/// hover, so the glyph is static here.
private struct ClaudeToolSeat: View {
    let call: ToolCall
    let symbol: String

    var body: some View {
        Group {
            if case .shell = call.detail {
                ClaudeGlyph(kind: .api, size: 14, color: ClaudePalette.tertiaryInk)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// The leading seat on the summary row (doc 08 §1.2): 16 × 16, the 14 × 14 activity icon at rest;
/// touch has no hover, so the chevron — up while open, down while a finger is down — shows only
/// then. There is no trailing chevron; the chevron lives in the seat.
private struct ClaudeLeadingSeat: View {
    let glyph: ClaudeGlyph.Kind
    let expanded: Bool
    @Environment(\.claudeRowPressed) private var pressed

    var body: some View {
        Group {
            if expanded {
                ClaudeGlyph(kind: .chevronUp, size: 14, color: ClaudePalette.tertiaryInk)
            } else if pressed {
                ClaudeGlyph(kind: .chevronDown, size: 14, color: ClaudePalette.tertiaryInk)
            } else {
                ClaudeGlyph(kind: glyph, size: 14, color: ClaudePalette.tertiaryInk)
            }
        }
        .frame(width: 16, height: 16)
    }
}

#endif
