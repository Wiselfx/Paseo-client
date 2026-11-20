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
    /// The agent's working directory: markdown images written `![a](~/shots/a.png)` or
    /// `![a](./a.png)` and authored links to files resolve against it (J2). Read inside a
    /// leaf view's body, like the other conversation values (R-1).
    var homeDirectory: String?
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
#endif
