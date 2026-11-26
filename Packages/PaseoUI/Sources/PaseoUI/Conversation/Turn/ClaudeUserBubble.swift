#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

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
    /// A rewind is in flight: the rewind items are disabled until it settles (upstream
    /// `rewind-menu.tsx` `isLocked`).
    var rewindInFlight: Bool = false
    /// This device's sent images, looked up by the send's `clientMessageId` (§9.5).
    /// Nil (another device, an evicted entry) draws nothing: no placeholder, no fetch.
    var clientMessageId: String? = nil
    /// When the daemon recorded the message; drawn under the bubble once it is acknowledged
    /// (upstream `message.tsx:423,527`, `user-message-timestamp`).
    var sentAt: Date? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Disk entries for a send whose memory seed is gone (relaunch, eviction).
    @State private var diskImages: [UIImage]? = nil

    /// Captured at insertion: true only for a message that was pending when it appeared
    /// (i.e. sent this session). History rows are never pending, so they never animate.
    @State private var entered: Bool
    /// The "Select text" sheet.
    @State private var showingText = false
    /// Counts copies so the confirmation haptic fires per tap.
    @State private var copyCount = 0

    init(
        text: String, isPending: Bool, rewindChoices: [RewindScope] = [],
        onRewind: ((RewindScope) -> Void)? = nil,
        rewindInFlight: Bool = false, clientMessageId: String? = nil, sentAt: Date? = nil
    ) {
        self.text = text
        self.isPending = isPending
        self.rewindChoices = rewindChoices
        self.onRewind = onRewind
        self.rewindInFlight = rewindInFlight
        self.clientMessageId = clientMessageId
        self.sentAt = sentAt
        self._entered = State(initialValue: !isPending)
    }

    var body: some View {
        // The bubble's width is decided once, by the column: a fixed inset on the leading side and
        // the text's own wrapped width, never an HStack/Spacer split that depends on the height
        // offered (the measure and the draw were offered different heights, so a bubble flipped
        // between wide and narrow while scrolling).
        VStack(alignment: .trailing, spacing: Space.xs) {
            bubble
                .padding(.leading, 42)
            if let sentAt, !isPending, !text.isEmpty {
                Text(PaseoFormat.messageTimestamp(sentAt))
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.trailing, Space.xs)
            }
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
            ForEach(sentImages.enumerated(), id: \.offset) { index, image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Metrics.userImageMaxHeight)
                    .clipShape(.rect(cornerRadius: Radius.sm))
                    .transition(.opacity)
                    .accessibilityLabel("Sent image \(index + 1)")
            }
            ForEach(reservedRatios.enumerated(), id: \.offset) { _, ratio in
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
            .foregroundStyle(Palette.onUserBubble)
            // Links in your bubble read in the bubble's own text colour: the link blue would vanish on blue.
            .tint(Palette.onUserBubble)
            .lineSpacing(4)
            .padding(.horizontal, 16)
            .padding(.vertical, Space.md)
            .background(Palette.userBubble, in: .rect(cornerRadius: Radius.bubble))
            .contentShape(
                .contextMenuPreview,
                RoundedRectangle(cornerRadius: Radius.bubble))
            .opacity(isPending ? 0.6 : 1)
            .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: isPending)
            .contextMenu { menuItems }
            .sheet(isPresented: $showingText) { MessageTextSheet(text: text) }
            .paseoFeedback(.light, trigger: copyCount)
    }

    @ViewBuilder private var menuItems: some View {
        Button("Copy", systemImage: "doc.on.doc", action: copyText)
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

    private func copyText() {
        Clipboard.copy(text)
        copyCount += 1
    }

    /// The plain text, or with its file paths as tappable links (M7g), memoized by text.
    @ViewBuilder private var bodyText: some View {
        Group {
            if let linked = FilePathLinks.bubbleText(text) {
                Text(linked)
            } else {
                Text(text)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A sent message rises 10 pt into place (fade-up, OCU §12.20).
    private var shownOffset: CGFloat {
        entered || reduceMotion ? 0 : 10
    }

    private var shownOpacity: Double {
        entered ? 1 : 0
    }
}
#endif
