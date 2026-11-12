#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import UIKit

// MARK: - RichActions (G1 §1.2)

// NOTE: RemoteImagePipeline/G2: `loadLocalImage` moves into `MediaPipeline`; the environment
// key stays — cards keep reading the same object (G-round contract §3: never two loaders).

/// The one object cards act through (G1 §1.2, R-2). Cards take values only — the tappable,
/// shareable, copyable things they need arrive here, injected once per conversation by
/// `ChatScreen` from the controller's verbs. A card outside a conversation (a preview) reads
/// nil and falls back to its inert rendering: pixels it already holds, or nothing to tap.
///
/// Narrow on purpose (R-1): turn-level verbs (rewind, fork, delete) stay on `ChatActions`,
/// which cards never observe, so a turn action never invalidates a card.
@MainActor @Observable
final class RichActions {
    /// Opens a `paseo-file://` path in the workspace file viewer. No-op until the host sets it.
    var openFile: (String) -> Void = { _ in }
    /// The §12 connection (path monitor + the host session's relay flag), mirrored by the
    /// conversation controller. Cards read only the derived policy (R-1).
    var linkCondition: MediaLinkCondition = .assumed
    /// The workspace daemon files resolve against (workspaceId). Nil outside a conversation:
    /// without it, local images render as path chips.
    var daemonWorkspaceID: String?
    /// Ordinary links: the host's handler (file links open the viewer, the rest fall through).
    /// Defaults to the application opener so a card without a host still does the obvious thing.
    var openURL: (URL) -> Void = { url in UIApplication.shared.open(url) }
    /// Copies text and confirms with the copy haptic (the D5 vocabulary: `light()` on copy).
    var copyText: (String) -> Void = { text in
        UIPasteboard.general.string = text
        Haptics.light()
    }
    /// Copies an image to the pasteboard. Defaults to the general pasteboard; the host
    /// overrides only if it needs more.
    var copyImage: (UIImage) -> Void = { image in
        UIPasteboard.general.image = image
        Haptics.light()
    }
    /// Lists a daemon directory without touching the Files page's state (G10 C10).
    /// Nil outside a conversation; nil entries keep the card honest about unknowns.
    var listDaemonDirectory: ((String, String) async -> [FileExplorerEntry]?)?
    /// Opens a file's diff (G6 C11): this turn's edit/write calls for the path, in
    /// order — the concatenated unified diffs, or the combined old-to-new — else the
    /// file viewer. No-op until the host sets it.
    var openDiff: (String, String) -> Void = { _, _ in }
    /// Jumps the transcript to a media-sheet item's turn (G12 C15). No-op until set.
    var openMediaItem: (ConversationMediaItem) -> Void = { _ in }
    /// Provider subagents by originating tool call id (C4 §9.4): mirrored from the
    /// store's subagent list, one write per change — the same pattern as
    /// `checkoutPR`. Rows read one small value that changes rarely (R-1).
    var subagentsByCallId: [String: ProviderSubagent] = [:]
    /// Pushes a provider subagent's read-only timeline (C4 §9.4). No-op until set.
    var openSubagent: (ProviderSubagent) -> Void = { _ in }
    /// The checkout's PR status (G9 C13), mirrored by the conversation controller.
    /// Cards read only this value; the subscription lives in the store (R-1).
    var checkoutPR: CheckoutPrStatus?
    /// Resolves a same-repo GitHub link through forge search (G9 C7). Nil outside a
    /// conversation, and nil for repos the lookup cannot see: the card degrades to
    /// the metadata link card.
    var githubLookup: ((GitHubURL) async -> GitHubLinkInfo?)?
    /// Opens the workspace panel (G9 C13): the PR pane lives there. No-op until set.
    var openPRPane: () -> Void = {}
    /// Opens an artifact full screen (G4/G5). No-op until the host sets it.
    var openArtifact: (ArtifactDocument) -> Void = { _ in }
    /// True while the artifact page covers the transcript (G4/G5): web cards yield
    /// their pooled slots and fall back to snapshots.
    var artifactPageOpen = false
    /// Adds an image to the composer tray (G3): the file name plus JPEG bytes, through the
    /// existing attachment path. No-op until the host sets it.
    var addImageToChat: (String, Data) -> Void = { _, _ in }
    /// Saves an image to Photos. Needs `NSPhotoLibraryAddUsageDescription` (G3 adds it);
    /// until then the system prompt speaks for itself on first use.
    var saveImage: (UIImage) -> Void = { image in
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}

private struct RichActionsKey: EnvironmentKey {
    static let defaultValue: RichActions? = nil
}

extension EnvironmentValues {
    /// The conversation's card verbs; nil outside a conversation (previews, the draft screen).
    var richActions: RichActions? {
        get { self[RichActionsKey.self] }
        set { self[RichActionsKey.self] = newValue }
    }
}

// MARK: - Chrome

/// The card family's container (G1 §1.1): the panel surface, the 0.5 pt card border, the
/// 12 pt continuous radius — the same chrome `RichCard` drew, now in one place.
///
/// The content is a constructed value, never a builder: card initializers take values only
/// (R-2), so a card is built as `PaseoCard(content: HStack { ... })`, not as a trailing closure.
struct PaseoCard<Content: View>: View {
    let content: Content

    init(content: Content) {
        self.content = content
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.md)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
            }
    }
}

/// The standard header strip: an optional 17 pt glyph, a 1–2 line title, an optional meta line.
/// A value (R-2); doubles as the card's accessibility label.
struct PaseoCardHeader: View, Equatable {
    let glyph: String?
    let title: String
    let meta: String?

    init(glyph: String? = nil, title: String, meta: String? = nil) {
        self.glyph = glyph
        self.title = title
        self.meta = meta
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            if let glyph {
                Image(systemName: glyph)
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if let meta {
                    Text(meta)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The media-card layout (G1 §1.1): the media slot sits on top, edge to edge and clipped to
/// the card, and an optional header strip goes below. With no header the media *is* the card
/// (C1: no metadata strip on images) — the panel never insets the pixels.
struct PaseoMediaCard<Media: View>: View {
    let media: Media
    let header: PaseoCardHeader?

    init(media: Media, header: PaseoCardHeader? = nil) {
        self.media = media
        self.header = header
    }

    var body: some View {
        VStack(spacing: 0) {
            media
            if let header {
                header
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
        .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
        }
    }
}

/// The row-card layout (G1 §1.1): a 56 pt minimum row — glyph, title, meta, one trailing
/// accessory. Text containers use `minHeight`, never `height`, so Dynamic Type grows the row.
struct PaseoRowCard<Accessory: View>: View {
    let glyph: String
    let title: String
    let meta: String?
    let accessory: Accessory

    init(glyph: String, title: String, meta: String? = nil, accessory: Accessory) {
        self.glyph = glyph
        self.title = title
        self.meta = meta
        self.accessory = accessory
    }

    var body: some View {
        PaseoCard(content:
            HStack(spacing: Space.sm) {
                Image(systemName: glyph)
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(minWidth: Metrics.hitSize - Space.md, alignment: .center)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    if let meta {
                        Text(meta)
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                accessory
            }
            .frame(minHeight: Metrics.rowCardMinHeight - Space.md * 2)
        )
    }
}

extension PaseoRowCard where Accessory == EmptyView {
    init(glyph: String, title: String, meta: String? = nil) {
        self.init(glyph: glyph, title: title, meta: meta, accessory: EmptyView())
    }
}

// MARK: - Press

/// The card press (G1 §1.2): the content settles to 98 % while held, through the feedback
/// token. `reduceMotion` is a value (R-2): the host reads the environment once and passes it
/// in, so the style itself observes nothing.
struct PaseoCardButtonStyle: ButtonStyle {
    var reduceMotion = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Metrics.cardPressScale : 1)
            .animation(
                Motion.feedback.resolved(reduceMotion: reduceMotion),
                value: configuration.isPressed)
    }
}

// MARK: - Context menu

/// The card menu (G1 §1.2): every card offers the same items in the same order, and only the
/// ones that apply. A nil slot omits its item; the order below is the §1.2 order: Open, Share,
/// Copy, Save to Photos, Open externally, View source, Show in Files.
///
/// Local presentation (a sheet, a source toggle, an in-app browser) arrives as the `on…`
/// closures, which flip view-local state; cross-cutting verbs (copy, save, external open,
/// Show in Files) go through `RichActions` from the environment. No haptic here: the system
/// already plays one when a context menu appears.
extension View {
    func paseoCardMenu(
        openTitle: String? = nil,
        onOpen: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        copyTitle: String? = nil,
        copyText: String? = nil,
        saveImage: UIImage? = nil,
        externalTitle: String? = nil,
        externalURL: URL? = nil,
        viewSourceTitle: String? = nil,
        onViewSource: (() -> Void)? = nil,
        filePath: String? = nil
    ) -> some View {
        modifier(PaseoCardMenuModifier(
            openTitle: openTitle, onOpen: onOpen,
            onShare: onShare,
            copyTitle: copyTitle, copyText: copyText,
            saveImage: saveImage,
            externalTitle: externalTitle, externalURL: externalURL,
            viewSourceTitle: viewSourceTitle, onViewSource: onViewSource,
            filePath: filePath))
    }
}

private struct PaseoCardMenuModifier: ViewModifier {
    let openTitle: String?
    let onOpen: (() -> Void)?
    let onShare: (() -> Void)?
    let copyTitle: String?
    let copyText: String?
    let saveImage: UIImage?
    let externalTitle: String?
    let externalURL: URL?
    let viewSourceTitle: String?
    let onViewSource: (() -> Void)?
    let filePath: String?

    @Environment(\.richActions) private var richActions

    func body(content: Content) -> some View {
        content.contextMenu {
            VStack {
                if let openTitle, let onOpen {
                    Button(openTitle, systemImage: "arrow.up.forward.app") { onOpen() }
                }
                if let onShare {
                    Button("Share", systemImage: "square.and.arrow.up") { onShare() }
                }
                if let copyTitle, let copyText {
                    Button(copyTitle, systemImage: "doc.on.doc") {
                        if let richActions {
                            richActions.copyText(copyText)
                        } else {
                            UIPasteboard.general.string = copyText
                            Haptics.light()
                        }
                    }
                }
                if let saveImage {
                    Button("Save to Photos", systemImage: "photo") {
                        if let richActions {
                            richActions.saveImage(saveImage)
                        } else {
                            UIImageWriteToSavedPhotosAlbum(saveImage, nil, nil, nil)
                        }
                    }
                }
                if let externalTitle, let externalURL {
                    Button(externalTitle, systemImage: "safari") {
                        if let richActions {
                            richActions.openURL(externalURL)
                        } else {
                            UIApplication.shared.open(externalURL)
                        }
                    }
                }
                if let viewSourceTitle, let onViewSource {
                    Button(viewSourceTitle, systemImage: "chevron.left.forwardslash.chevron.right") {
                        onViewSource()
                    }
                }
                if let filePath {
                    Button("Show in Files", systemImage: "folder") {
                        richActions?.openFile(filePath)
                    }
                }
            }
        }
    }
}

// MARK: - Accessibility

extension View {
    /// One accessibility element per card (G1 §1.5): kind + title + meta. A card whose whole
    /// body is one action also takes the button trait; a card with several controls leaves its
    /// children visible and labels its regions instead.
    func paseoCardAccessibility(
        kind: String, title: String, meta: String? = nil, isButton: Bool = false
    ) -> some View {
        self.accessibilityElement(children: .combine)
            .accessibilityLabel(
                ([kind, title] + (meta.map { [$0] } ?? [])).filter { !$0.isEmpty }
                    .joined(separator: ", "))
            .accessibilityAddTraits(isButton ? .isButton : [])
    }
}
#endif
