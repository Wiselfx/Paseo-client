#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One retained emulator in the stage. It reads the uploader itself, so a chunk of upload
/// progress re-evaluates this view alone and not the whole terminal page.
struct TerminalStageEntry: View {
    let store: TerminalsStore
    let uploader: ConversationUpload
    let terminalId: String
    let isSelected: Bool
    let isOutgoing: Bool
    let onExit: (String?) -> Void
    let onOutput: () -> Void
    let onOpenLink: (TerminalLinkTarget) -> Void
    let onAttach: () -> Void

    /// The key bar's progress row, straight off the T14 uploader (one upload at a time).
    private var upload: TerminalUploadSnapshot? {
        guard isSelected, uploader.isUploading, let name = uploader.fileName else { return nil }
        return TerminalUploadSnapshot(fileName: name, progress: uploader.progress)
    }

    var body: some View {
        PaseoTerminalView(
            store: store,
            terminalId: terminalId,
            isVisible: isSelected,
            onExit: onExit,
            onOutput: onOutput,
            onOpenLink: onOpenLink,
            upload: upload,
            onAttach: onAttach,
            onCancelUpload: { uploader.cancel() })
        // The terminal the switch just left stays opaque for the length of the fade, so the
        // incoming one fades in over it instead of both fading toward the canvas. `select` clears
        // it again when the fade ends, which takes it out of the composite.
        .opacity(isSelected || isOutgoing ? 1 : 0)
        .allowsHitTesting(isSelected)
        .accessibilityHidden(!isSelected)
    }
}
#endif
