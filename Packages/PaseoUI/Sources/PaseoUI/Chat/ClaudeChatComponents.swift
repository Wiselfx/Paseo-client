#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Terminal-style output: an optional command line, then output that scrolls both ways inside a
/// capped height, so a 2,000-line log never takes over the conversation.
struct ClaudeCodeBlock: View {
    var title: String?
    var command: String?
    var output: String?
    var status: ToolCallPresentation.Status
    var maxHeight: CGFloat

    private let typography = ClaudeTypography()

    init(
        title: String? = nil, command: String? = nil, output: String?,
        status: ToolCallPresentation.Status = .succeeded, maxHeight: CGFloat = 260
    ) {
        self.title = title
        self.command = command
        self.output = output
        self.status = status
        self.maxHeight = maxHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if command != nil || title != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ClaudeStatusDot(status: status)
                    if let title {
                        Text(title).font(typography.mono(12.5)).foregroundStyle(
                            ClaudePalette.secondaryInk)
                    }
                    if let command {
                        Text(command).font(typography.mono(12.5)).foregroundStyle(
                            ClaudePalette.primaryInk
                        ).lineLimit(3)
                    }
                    Spacer(minLength: 8)
                    ClaudeCopyButton(text: [command, output].compactMap { $0 }.joined(separator: "\n"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                if hasOutput { ClaudeDivider() }
            }
            if hasOutput, let output {
                ScrollView([.vertical, .horizontal]) {
                    Text(output)
                        .font(typography.mono(12.5))
                        .foregroundStyle(ClaudePalette.primaryInk.opacity(0.85))
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
        .background(ClaudePalette.codeBackground, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
        }
    }

    private var hasOutput: Bool { !(output ?? "").isEmpty }
}

/// The tool call's status, as a 6 pt dot with a spinner while it runs.
struct ClaudeStatusDot: View {
    var status: ToolCallPresentation.Status

    var body: some View {
        switch status {
        case .running: ProgressView().controlSize(.mini)
        case .succeeded: Circle().fill(ClaudePalette.successInk).frame(width: 6, height: 6)
        case .failed: Circle().fill(ClaudePalette.failureInk).frame(width: 6, height: 6)
        case .canceled: Circle().strokeBorder(ClaudePalette.tertiaryInk, lineWidth: 1).frame(width: 6, height: 6)
        }
    }
}

/// The label for a rewind scope in the menu and the confirm dialog (upstream copy, en.ts).
func rewindScopeTitle(_ scope: RewindScope) -> String {
    switch scope {
    case .conversation: "Rewind conversation"
    case .files: "Rewind files"
    case .both: "Rewind conversation and files"
    case .unknown: "Rewind to here"
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
            Haptics.selection()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "square.on.square")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(copied ? ClaudePalette.primaryInk : ClaudePalette.tertiaryInk)
                .frame(width: 28, height: 28)
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
/// Long-press → "Rewind to here" appears only once the provider acknowledged the message
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
    /// M7h message actions (rewind-based): Edit puts this text back in the composer and rewinds
    /// to before this message; Rerun does the same and resends it.
    var canRewrite: Bool = false
    var onEdit: (() -> Void)? = nil
    var onRerun: (() -> Void)? = nil
    /// DSH "Retract this message": forks before this message and puts the text back in the new
    /// session's composer (`message-actions.ts:197-207`). Nil hides the item — no host support, no
    /// settled turn, or nothing above the message to fork from.
    var onRetract: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Captured at insertion: true only for a message that was pending when it appeared
    /// (i.e. sent this session). History rows are never pending, so they never animate.
    @State private var entered: Bool
    /// The "Select text" sheet.
    @State private var showingText = false

    /// The bubble's shape, shared by the fill and the context-menu preview.
    private static let bubbleRadius: CGFloat = 20

    init(
        text: String, isPending: Bool, rewindChoices: [RewindScope] = [],
        onRewind: ((RewindScope) -> Void)? = nil, attributed: AttributedString? = nil,
        canRewrite: Bool = false, onEdit: (() -> Void)? = nil, onRerun: (() -> Void)? = nil,
        onRetract: (() -> Void)? = nil
    ) {
        self.text = text
        self.isPending = isPending
        self.rewindChoices = rewindChoices
        self.onRewind = onRewind
        self.attributed = attributed
        self.canRewrite = canRewrite
        self.onEdit = onEdit
        self.onRerun = onRerun
        self.onRetract = onRetract
        self._entered = State(initialValue: !isPending)
    }

    var body: some View {
        HStack {
            Spacer(minLength: 42)
            bubble
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .scaleEffect(shownScale, anchor: .bottomTrailing)
        .opacity(shownOpacity)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.2)
                : .timingCurve(0.22, 1, 0.36, 1, duration: 0.2),
            value: entered)
        .onAppear { entered = true }
    }

    /// The filled bubble, and the thing the context-menu preview shows.
    private var bubble: some View {
        bodyText
            .font(ClaudeTypography().sans(14))
            .foregroundStyle(ClaudePalette.primaryInk)
            .lineSpacing(8) // 14 / 22
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ClaudePalette.userBubble, in: .rect(cornerRadius: Self.bubbleRadius, style: .continuous)
            )
            .contentShape(
                .contextMenuPreview,
                RoundedRectangle(cornerRadius: Self.bubbleRadius, style: .continuous))
            .opacity(isPending ? 0.6 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isPending)
            .contextMenu { menuItems }
            .sheet(isPresented: $showingText) { MessageTextSheet(text: text) }
    }

    @ViewBuilder private var menuItems: some View {
        Button("Copy", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = text
            Haptics.selection()
        }
        Button("Select text", systemImage: "textformat.alt") {
            showingText = true
        }
        if let onRewind, !rewindChoices.isEmpty {
            Divider()
            if rewindChoices.count == 1, let scope = rewindChoices.first {
                Button("Rewind to here", systemImage: "arrow.uturn.left") { onRewind(scope) }
            } else {
                Menu("Rewind to here", systemImage: "arrow.uturn.left") {
                    ForEach(rewindChoices, id: \.self) { scope in
                        Button(rewindScopeTitle(scope)) { onRewind(scope) }
                    }
                }
            }
        }
        if let onEdit, let onRerun, canRewrite {
            Divider()
            Button("Edit", systemImage: "pencil") { onEdit() }
            Button("Rerun", systemImage: "arrow.clockwise") { onRerun() }
        }
        if let onRetract {
            Button("Retract this message", systemImage: "arrow.uturn.backward") { onRetract() }
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

    private var shownScale: CGFloat {
        entered || reduceMotion ? 1 : 0.96
    }

    private var shownOpacity: Double {
        entered ? 1 : 0
    }
}

/// Assistant prose: the serif Markdown renderer, one place for the theme.
/// `isStreaming` lets DSH's new-text reveal fade in only what actually arrives while you watch.
struct ClaudeProse: View {
    var markdown: String
    var typography: ClaudeTypography
    var onAction: (MarkdownAction) -> Void
    /// Reads a workspace image through the daemon (M5b); nil renders local image paths as chips.
    var localImageLoader: ((String) async -> UIImage?)? = nil
    /// True while the producing turn is running — assistant prose arriving live fades in.
    var isStreaming: Bool = false

    var body: some View {
        ClaudeRevealProse(
            markdown: markdown, theme: Self.theme(typography), onAction: onAction,
            isStreaming: isStreaming, localImageLoader: localImageLoader,
            imageContent: proseImageContent)
    }

    /// `![alt](url)` → `ProseMarkdownImage`; remote hosts ride AsyncImage, workspace paths the
    /// caller's loader. Always non-nil so prose images render instead of degrading to text.
    private var proseImageContent: (MarkdownImage) -> AnyView {
        let loader = localImageLoader
        return { image in
            AnyView(ProseMarkdownImage(image: image, localImageLoader: loader))
        }
    }

    static func theme(_ typography: ClaudeTypography) -> ClaudeMarkdownTheme {
        var theme = ClaudeMarkdownTheme(serifName: typography.resolvedSerifName, bodySize: 14)
        theme.foreground = ClaudePalette.primaryInk
        theme.secondary = ClaudePalette.secondaryInk
        theme.link = ClaudePalette.proseLink
        theme.codeBackground = ClaudePalette.codeSurface
        theme.inlineCodeBackground = ClaudePalette.inlineCodeFill
        theme.inlineCodeForeground = ClaudePalette.primaryInk
        theme.codeFont = typography.mono(13, relativeTo: .body)
        theme.blockSpacing = 12
        theme.lineSpacing = 9 // 14 / 23
        return theme
    }
}
#endif
