#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The parsed terminal, by output identity: every remount reads the same parse
/// synchronously instead of re-parsing (a remount storm on a 1 MB log is a jump
/// plus repeated work). `NSCache` reads are O(1) and thread-safe.
private enum TerminalParseCache {
    nonisolated(unsafe) private static let table: NSCache<NSString, ParsedTerminalBox> = {
        let cache = NSCache<NSString, ParsedTerminalBox>()
        cache.countLimit = 16
        return cache
    }()

    /// Stable per content: length plus hash (a display cache — a collision shows
    /// the wrong tail until the output changes again, at ~2^-64 odds).
    static func key(for output: String) -> String {
        "\(output.count)-\(output.hashValue)"
    }

    static func entry(for output: String) -> ClaudeCodeBlock.ParsedTerminal? {
        table.object(forKey: key(for: output) as NSString)?.value
    }

    static func store(_ parsed: ClaudeCodeBlock.ParsedTerminal, for output: String) {
        table.setObject(ParsedTerminalBox(value: parsed), forKey: key(for: output) as NSString)
    }
}

/// `NSCache` holds objects: the parse it carries.
private final class ParsedTerminalBox {
    let value: ClaudeCodeBlock.ParsedTerminal
    init(value: ClaudeCodeBlock.ParsedTerminal) { self.value = value }
}

/// Terminal-style output: an optional command line, then output that scrolls both ways inside a
/// capped height, so a 2,000-line log never takes over the conversation.
struct ClaudeCodeBlock: View {
    var title: String?
    var command: String?
    var output: String?
    var status: ToolCallPresentation.Status
    var maxHeight: CGFloat
    /// Terminal mode (G8 C12): ANSI colors, a 12-line tail, the exit pill and the
    /// test chip. Parses off main, once per output (never per body pass).
    var terminal: Bool = false
    /// The shell exit code, for the exit pill. Nil when the call never reported one.
    var exitCode: Double? = nil

    /// The parsed terminal: tail runs for the card, full runs for Copy all, the
    /// capped sheet runs for Show all (a SwiftUI `Text` with 1 MB of
    /// `AttributedString` is very slow), the test summary for the chip, the built
    /// sheet `AttributedString` (once per parse, cached here), and the total line
    /// count for the Show-all label.
    struct ParsedTerminal: Equatable {
        var tail: [AnsiRun]
        var full: [AnsiRun]
        var sheet: [AnsiRun]
        var sheetAttributed: AttributedString
        var summary: TestSummary?
        var lineCount: Int
    }

    @State private var parsed: ParsedTerminal?
    @State private var showAll = false

    /// The sheet's line cap (G8 review): full output scrolls nowhere fast.
    nonisolated private static let sheetLines = 2000

    init(
        title: String? = nil, command: String? = nil, output: String?,
        status: ToolCallPresentation.Status = .succeeded, maxHeight: CGFloat = 260,
        terminal: Bool = false, exitCode: Double? = nil
    ) {
        self.title = title
        self.command = command
        self.output = output
        self.status = status
        self.maxHeight = maxHeight
        self.terminal = terminal
        self.exitCode = exitCode
    }

    /// The last 12 lines: the tail that carries the verdict (G8 C12).
    nonisolated private static let tailLines = 12

    private var copyText: String {
        if let parsed {
            return parsed.full.map(\.text).joined()
        }
        return [command, output].compactMap { $0 }.joined(separator: "\n")
    }

    /// Exit code as a StatePill: quiet success for 0, failure ink otherwise (G8 C12).
    @ViewBuilder private var exitPill: some View {
        if let exitCode {
            let code = Int(exitCode)
            StatePill("Exit \(code)", tone: code == 0 ? .success : .failure)
        }
    }

    /// The test chip: "{passed} passed · {failed} failed" when a known runner's
    /// summary parsed, nothing otherwise (never an invented count).
    @ViewBuilder private var testChip: some View {
        if let summary = parsed?.summary, summary.hasSummary {
            StatePill(summary.chipText, tone: summary.failed > 0 ? .failure : .success)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if command != nil || title != nil || terminal {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ClaudeStatusDot(status: status)
                    if let title {
                        Text(title).font(.paseo(.codeSmall)).foregroundStyle(
                            Palette.secondaryInk)
                    }
                    if let command {
                        Text(command).font(.paseo(.codeSmall)).foregroundStyle(
                            Palette.ink
                        ).lineLimit(3)
                    }
                    Spacer(minLength: 8)
                    testChip
                    exitPill
                    ClaudeCopyButton(text: copyText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                if hasOutput { ClaudeDivider() }
            }
            if hasOutput {
                if terminal, let output {
                    terminalOutput(output)
                } else if let output {
                    ScrollView([.vertical, .horizontal]) {
                        Text(output)
                            .font(.paseo(.codeSmall))
                            .foregroundStyle(Palette.ink.opacity(0.85))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: maxHeight)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: terminal ? output : nil) { await parseTerminal() }
        .background(Palette.codeSurface, in: .rect(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.cardBorder, lineWidth: 1)
        }
        .codeTypeScale()
    }

    /// Parses the output off main when it changes (never per body pass): ANSI runs,
    /// the tail slice, the capped sheet slice, and the test summary. The sheet's
    /// `AttributedString` builds once here (never per body pass) and rides with the
    /// parse into the cache. State writes only when the output changes.
    @MainActor
    private func parseTerminal() async {
        guard terminal, let output, !output.isEmpty else {
            parsed = nil
            return
        }
        if let cached = TerminalParseCache.entry(for: output) {
            parsed = cached
            return
        }
        // The parse runs off main; the AttributedString (fonts and colours are
        // main-actor tokens) is built once here, from the capped sheet runs.
        let parts = await Task.detached(priority: .userInitiated) {
            () -> (tail: [AnsiRun], full: [AnsiRun], sheet: [AnsiRun], summary: TestSummary?, lines: Int) in
            let runs = AnsiText.parse(output)
            let tail = AnsiText.tail(runs, maxLines: Self.tailLines)
            let sheet = AnsiText.tail(runs, maxLines: Self.sheetLines)
            let summary = TestSummaryParser.parse(output)
            let lines = runs.reduce(0) { $0 + $1.text.filter { $0.isNewline }.count }
            return (tail, runs, sheet, summary, lines)
        }.value
        guard !Task.isCancelled else { return }
        let result = ParsedTerminal(
            tail: parts.tail, full: parts.full, sheet: parts.sheet,
            sheetAttributed: Self.attributedText(parts.sheet), summary: parts.summary,
            lineCount: parts.lines)
        TerminalParseCache.store(result, for: output)
        parsed = result
    }

    /// The tail in ANSI colors, with "Show all" opening the capped sheet. Until the
    /// first parse lands, the plain last 12 lines hold the final box height and only
    /// the colors change — no jump, no repeated work on remount.
    private func terminalOutput(_ output: String) -> some View {
        let display = parsed ?? TerminalParseCache.entry(for: output)
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView([.vertical, .horizontal]) {
                if let display {
                    Text(Self.attributedText(display.tail))
                        .font(.paseo(.codeSmall))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(AnsiText.plainTail(output, maxLines: Self.tailLines))
                        .font(.paseo(.codeSmall))
                        .foregroundStyle(Palette.ink.opacity(0.85))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: true)
            if let display, display.lineCount > Self.tailLines {
                Button("Show all \(display.lineCount) lines") { showAll = true }
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(minHeight: Metrics.hitSize)
                    .accessibilityHint("Opens the full terminal output")
                    .sheet(isPresented: $showAll) {
                        SheetScaffold("Output", detents: .large) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    if display.lineCount > Self.sheetLines {
                                        Text(
                                            "Showing the last \(Self.sheetLines) of \(display.lineCount) lines"
                                        )
                                        .font(.paseo(.caption))
                                        .foregroundStyle(Palette.secondaryInk)
                                    }
                                    Spacer(minLength: Space.sm)
                                    ClaudeCopyButton(text: copyText, label: "Copy all")
                                }
                                .padding(.horizontal, Space.md)
                                .padding(.vertical, Space.sm)
                                ScrollView([.vertical, .horizontal]) {
                                    Text(display.sheetAttributed)
                                        .font(.paseo(.codeSmall))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(Space.md)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
            }
        }
    }

    /// Runs to a colored `Text`: the tail builds per paint (12 lines, cheap); the
    /// sheet builds once per parse and rides with it.
    private static func attributedText(_ runs: [AnsiRun]) -> AttributedString {
        var out = AttributedString()
        for run in runs {
            var part = AttributedString(run.text)
            part.font = .paseo(.codeSmall)
            if run.style.bold { part.font = part.font?.bold() }
            if let foreground = run.style.foreground {
                part.foregroundColor = Palette.ansi(foreground)
            } else {
                part.foregroundColor = Palette.ink.opacity(0.85)
            }
            if run.style.dim, let color = part.foregroundColor {
                part.foregroundColor = color.opacity(0.65)
            }
            if let background = run.style.background {
                part.backgroundColor = Palette.ansi(background)
            }
            if run.style.underline { part.underlineStyle = .single }
            if run.style.strikethrough { part.strikethroughStyle = .single }
            out += part
        }
        return out
    }

    private var hasOutput: Bool { !(output ?? "").isEmpty }
}

/// The tool call's status, as a 6 pt dot with a spinner while it runs.
struct ClaudeStatusDot: View {
    var status: ToolCallPresentation.Status

    var body: some View {
        switch status {
        case .running: ProgressView().controlSize(.mini)
        case .succeeded: Circle().fill(Palette.successInk).frame(width: 6, height: 6)
        case .failed: Circle().fill(Palette.failureInk).frame(width: 6, height: 6)
        case .canceled: Circle().strokeBorder(Palette.tertiaryInk, lineWidth: 1).frame(width: 6, height: 6)
        }
    }
}

/// The label for a rewind scope in the menu and the confirm dialog (upstream copy, en.ts).
func rewindScopeTitle(_ scope: RewindScope) -> String {
    switch scope {
    case .conversation: "Rewind conversation"
    case .files: "Rewind files"
    case .both: "Rewind conversation and files"
    case .unknown: "Rewind to this message"
    }
}

/// 28 × 28 copy affordance, the size DSH uses for its own row buttons.
struct ClaudeCopyButton: View {
    var text: String
    var label = "Copy"
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            Haptics.light()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "square.on.square")
                .font(.glyph(.regular, weight: .light))
                .foregroundStyle(copied ? Palette.ink : Palette.tertiaryInk)
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : label)
    }
}

/// What you said: the ClaudeUI bubble, trailing, with a pending state while the daemon confirms it.
/// A message sent this session grows into place (scale 0.96 + fade, DSH chat-send);
/// Reduce Motion fades. History bubbles never animate.
///
/// Long-press → "Rewind to this message" appears only once the provider acknowledged the message
/// (`rewindChoices` non-empty). The actual rewind confirm lives in the transcript.
///
/// The long-press preview is the bubble itself, clipped to its rounded shape (UX spec §4.3),
/// and text selection moved out of the bubble into "Select text": selection drawn inside the
/// padded, filled bubble painted a full-width rectangle (B12).
struct ClaudeUserBubble: View {
    var text: String
    var isPending: Bool
    /// The scopes the provider supports, in menu order; empty hides the rewind item.
    var rewindChoices: [RewindScope] = []
    /// Called with the chosen scope; the parent presents the confirmation dialog.
    var onRewind: ((RewindScope) -> Void)? = nil
    /// M7g file mentions: a pre-formatted body with tappable `paseo-file:` links. Nil (the
    /// default) renders the plain `text` unchanged.
    var attributed: AttributedString? = nil
    /// A rewind is in flight: the rewind items are disabled until it settles (upstream
    /// `rewind-menu.tsx` `isLocked`).
    var rewindInFlight: Bool = false
    /// This device's sent images, looked up by the send's `clientMessageId` (§9.5).
    /// Nil (another device, an evicted entry) draws nothing: no placeholder, no fetch.
    var clientMessageId: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Disk entries for a send whose memory seed is gone (relaunch, eviction).
    @State private var diskImages: [UIImage]? = nil

    /// Captured at insertion: true only for a message that was pending when it appeared
    /// (i.e. sent this session). History rows are never pending, so they never animate.
    @State private var entered: Bool
    /// The "Select text" sheet.
    @State private var showingText = false

    /// The bubble's shape, shared by the fill and the context-menu preview.

    init(
        text: String, isPending: Bool, rewindChoices: [RewindScope] = [],
        onRewind: ((RewindScope) -> Void)? = nil, attributed: AttributedString? = nil,
        rewindInFlight: Bool = false, clientMessageId: String? = nil
    ) {
        self.text = text
        self.isPending = isPending
        self.rewindChoices = rewindChoices
        self.onRewind = onRewind
        self.attributed = attributed
        self.rewindInFlight = rewindInFlight
        self.clientMessageId = clientMessageId
        self._entered = State(initialValue: !isPending)
    }

    var body: some View {
        HStack {
            Spacer(minLength: 42)
            bubble
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .offset(y: shownOffset)
        .opacity(shownOpacity)
        .animation(
            reduceMotion
                ? Motion.fade.animation
                : Motion.bubbleEnter.animation,
            value: entered)
        .onAppear { entered = true }
        // Disk fills what memory lost (relaunch, eviction): one lookup per send,
        // never per body pass. The manifest loads first so the boxes reserve before
        // the pixels land. Unknown stays empty — no box, no placeholder, no fetch.
        .task(id: clientMessageId) {
            guard let id = clientMessageId else { return }
            await UserImageCache.shared.ensureManifestLoaded()
            guard UserImageCache.shared.memoryThumbnails(for: id) == nil else { return }
            diskImages = await UserImageCache.shared.diskThumbnails(for: id)
        }
    }

    /// This device's sent images for the send, memory first: the seed lands at send
    /// time, disk fills history after a relaunch. Unknown stays empty.
    private var sentImages: [UIImage] {
        if let id = clientMessageId,
            let memory = UserImageCache.shared.memoryThumbnails(for: id)
        {
            return memory
        }
        return diskImages ?? []
    }

    /// Reserved boxes from the manifest: the bubble keeps its height while the
    /// pixels load, so nothing jumps. No manifest entry means no box at all.
    private var reservedRatios: [CGFloat] {
        if !sentImages.isEmpty { return [] }
        guard let id = clientMessageId else { return [] }
        return UserImageCache.shared.manifestRatios(for: id) ?? []
    }

    /// The filled bubble, and the thing the context-menu preview shows.
    private var bubble: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(Array(sentImages.enumerated()), id: \.offset) { index, image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Metrics.userImageMaxHeight)
                    .clipShape(.rect(cornerRadius: Radius.sm))
                    .transition(.opacity)
                    .accessibilityLabel("Sent image \(index + 1)")
            }
            ForEach(Array(reservedRatios.enumerated()), id: \.offset) { _, ratio in
                Rectangle()
                    .fill(.clear)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
            bodyText
        }
        .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: sentImages.count)
            // UX-SPEC §4.1 (amended): the user bubble is 17 pt with 4 pt line spacing.
            .font(.paseo(.body))
            .foregroundStyle(Palette.ink)
            .lineSpacing(4)
            .padding(.horizontal, 16)
            .padding(.vertical, Space.md)
            .background(
                Palette.userBubble, in: .rect(cornerRadius: Radius.bubble, style: .continuous)
            )
            .contentShape(
                .contextMenuPreview,
                RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous))
            .opacity(isPending ? 0.6 : 1)
            .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: isPending)
            .contextMenu { menuItems }
            .sheet(isPresented: $showingText) { MessageTextSheet(text: text) }
    }

    @ViewBuilder private var menuItems: some View {
        Button("Copy", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = text
            Haptics.light()
        }
        Button("Select text", systemImage: "textformat.alt") {
            showingText = true
        }
        if let onRewind, !rewindChoices.isEmpty {
            Divider()
            // Upstream: rewind.tooltip, packages/app/src/i18n/resources/en.ts:2011.
            if rewindChoices.count == 1, let scope = rewindChoices.first {
                Button(rewindScopeTitle(scope), systemImage: "arrow.uturn.left") { onRewind(scope) }
                    .disabled(rewindInFlight)
            } else {
                Menu("Rewind to this message", systemImage: "arrow.uturn.left") {
                    ForEach(rewindChoices, id: \.self) { scope in
                        Button(rewindScopeTitle(scope)) { onRewind(scope) }
                    }
                }
                .disabled(rewindInFlight)
            }
        }
    }

    /// The plain text, or the M7g-formatted body with tappable file links.
    @ViewBuilder private var bodyText: some View {
        if let attributed {
            Text(attributed)
        } else {
            Text(text)
        }
    }

    /// A sent message rises 10 pt into place (fade-up, OCU §12.20).
    private var shownOffset: CGFloat {
        entered || reduceMotion ? 0 : 10
    }

    private var shownOpacity: Double {
        entered ? 1 : 0
    }
}

/// Assistant prose: the serif Markdown renderer, one place for the theme.
/// `isStreaming` lets DSH's new-text reveal fade in only what actually arrives while you watch.
struct ClaudeProse: View {
    var markdown: String
    var onAction: (MarkdownAction) -> Void
    /// True while the producing turn is running — assistant prose arriving live fades in.
    var isStreaming: Bool = false

    var body: some View {
        ClaudeRevealProse(
            markdown: markdown, theme: Self.theme(), onAction: onAction,
            isStreaming: isStreaming,
            imageContent: proseImageContent)
    }

    /// `![alt](url)` → `ProseMarkdownImage`; remote hosts and workspace paths both ride the
    /// shared `MediaPipeline`. Always non-nil so prose images render instead of degrading
    /// to text.
    private var proseImageContent: (MarkdownImage) -> AnyView {
        { image in
            AnyView(ProseMarkdownImage(image: image))
        }
    }

    static func theme(bodySize: CGFloat = Typography.chatBodySize) -> ClaudeMarkdownTheme {
        // Claude iOS chats at a 17 pt serif body (V5); the markdown *file preview* keeps the
        // research document's 14 pt, because UX-SPEC §6 freezes those previews.
        let chat = bodySize >= Typography.chatBodySize
        var theme = ClaudeMarkdownTheme(serifName: ProseFonts.serifName, bodySize: bodySize)
        theme.foreground = Palette.ink
        theme.secondary = Palette.secondaryInk
        theme.link = Palette.proseLink
        theme.codeBackground = Palette.codeSurface
        theme.inlineCodeBackground = Palette.inlineCodeFill
        theme.inlineCodeForeground = Palette.ink
        theme.codeFont = ProseFonts.mono(size: chat ? 15 : 13)
        theme.blockSpacing = chat ? 14 : 12
        theme.lineSpacing = chat ? 8 : 9 // chat: 17 / ~25; previews: 14 / 23
        return theme
    }
}
#endif
