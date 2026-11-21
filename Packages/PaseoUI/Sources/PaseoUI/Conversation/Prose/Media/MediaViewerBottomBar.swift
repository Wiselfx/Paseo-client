#if canImport(UIKit)
import SwiftUI

/// The viewer's bottom bar: Share, Copy, Save to Photos, Show in Files, Live Text and Add to
/// chat on one glass capsule. It draws state and reports taps; the viewer owns the verbs.
struct MediaViewerBottomBar: View {
    /// A decoded image is on hand: Share, Save and Add to chat need it.
    let hasImage: Bool
    /// Copy works from the decoded image, or from a remote link when nothing has decoded yet.
    let canCopy: Bool
    let showsFiles: Bool
    let showsLiveText: Bool
    let liveTextMode: Bool
    let onShare: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onShowInFiles: () -> Void
    let onToggleLiveText: () -> Void
    let onAddToChat: () -> Void

    private var liveTextTitle: LocalizedStringKey {
        liveTextMode ? "Hide text" : "Show text"
    }

    var body: some View {
        HStack(spacing: 0) {
            ViewerChromeButton(
                title: "Share image", systemImage: "square.and.arrow.up", action: onShare)
                .disabled(!hasImage)
            ViewerChromeButton(
                title: "Copy image", systemImage: "doc.on.doc", action: onCopy)
                .disabled(!canCopy)
            ViewerChromeButton(
                title: "Save to Photos", systemImage: "photo", action: onSave)
                .disabled(!hasImage)
            if showsFiles {
                ViewerChromeButton(
                    title: "Show in Files", systemImage: "folder", action: onShowInFiles)
            }
            if showsLiveText {
                ViewerChromeButton(
                    title: liveTextTitle, systemImage: "text.viewfinder",
                    action: onToggleLiveText)
            }
            ViewerChromeButton(
                title: "Add to chat", systemImage: "plus.bubble", action: onAddToChat)
                .disabled(!hasImage)
        }
        .glassEffect(in: .capsule)
        .padding(.horizontal, Space.md)
        .padding(.bottom, Space.md)
    }
}
#endif
