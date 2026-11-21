#if canImport(UIKit)
import SwiftUI
import UIKit
import VisionKit

// MARK: - MediaViewerView (G3 §4.6)

/// The one full-screen viewer for every visual in the app (G3): chat images, galleries,
/// Mermaid snapshots, Files-panel images, inline prose images. A UIKit pager (R-3) does the
/// finger-tracked work — swipe between pages, pinch and double-tap zoom, drag-down dismiss —
/// and SwiftUI hosts the content plus this chrome, learning only open/closed, the page and
/// the few values the chrome draws (R-1).
///
/// Entrance is the system zoom from the exact thumbnail (`matchedTransitionSource` on the
/// card, `.navigationTransition(.zoom)` here); Reduce Motion gets the fade. VoiceOver hears
/// one announcement per page ("Image 2 of 5, alt") and Escape closes.
struct MediaViewerView: View {
    let items: [MediaViewerItem]
    /// The matched-transition source id, shared with the card's `matchedTransitionSource`.
    let sourceID: String
    let namespace: Namespace.ID
    let onClose: () -> Void

    @Binding var selection: Int

    @Environment(\.richActions) private var richActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var chromeVisible = true
    /// The current page's full image, reported by the pager. Drives Copy and Add to chat.
    @State private var currentImage: UIImage?
    /// Set by the pager's Live Text analysis (off main): the button appears only when found.
    @State private var liveTextAvailable = false
    @State private var liveTextMode = false
    @State private var shareItem: ShareableImage?

    private var clampedSelection: Int {
        min(max(selection, 0), max(items.count - 1, 0))
    }

    private var currentItem: MediaViewerItem? {
        guard items.indices.contains(clampedSelection) else { return nil }
        return items[clampedSelection]
    }

    var body: some View {
        ZStack {
            MediaViewerPager(
                items: items,
                selection: $selection,
                chromeVisible: $chromeVisible,
                currentImage: $currentImage,
                liveTextAvailable: $liveTextAvailable,
                liveTextMode: liveTextMode,
                onClose: onClose,
                reduceMotion: reduceMotion)
                .ignoresSafeArea()
            if chromeVisible {
                VStack {
                    MediaViewerTopBar(
                        position: clampedSelection, count: items.count,
                        fileName: currentItem?.fileName,
                        announcement: pageAnnouncement, onClose: onClose)
                    Spacer(minLength: 0)
                    MediaViewerBottomBar(
                        hasImage: currentImage != nil,
                        canCopy: currentImage != nil || currentItem?.fullSource != nil,
                        showsFiles: currentItem?.filePath != nil,
                        showsLiveText: liveTextAvailable,
                        liveTextMode: liveTextMode,
                        onShare: shareCurrentImage,
                        onCopy: copyCurrentImage,
                        onSave: saveCurrentImage,
                        onShowInFiles: showCurrentInFiles,
                        onToggleLiveText: { liveTextMode.toggle() },
                        onAddToChat: addCurrentToChat)
                }
                .transition(.opacity)
            }
        }
        .background(.clear)
        .environment(\.colorScheme, .dark)
        // Clear so the drag can fade the UIKit backdrop onto the transcript behind.
        .presentationBackground(.clear)
        // Reduce Motion gets the system default cover transition (a cross-dissolve),
        // never the zoom: the two transition types cannot mix in one ternary.
        .modifier(MediaViewerTransition(sourceID: sourceID, namespace: namespace, reduceMotion: reduceMotion))
        .accessibilityAction(.escape) { onClose() }
        .onChange(of: selection) { _, _ in
            // One announcement per page; the label carries kind + position + alt (G3 §1.5).
            liveTextMode = false
            UIAccessibility.post(
                notification: .announcement, argument: pageAnnouncement)
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.image])
        }
        .accessibilityIdentifier("media.viewer")
    }

    private var pageAnnouncement: String {
        let position = items.count > 1 ? "Image \(clampedSelection + 1) of \(items.count)" : "Image"
        let alt = currentItem?.alt ?? ""
        return alt.isEmpty ? position : "\(position), \(alt)"
    }

    // MARK: Actions

    private func shareCurrentImage() {
        shareItem = currentImage.map { ShareableImage(image: $0) }
    }

    private func saveCurrentImage() {
        guard let currentImage else { return }
        if let richActions {
            richActions.saveImage(currentImage)
        } else {
            UIImageWriteToSavedPhotosAlbum(currentImage, nil, nil, nil)
        }
    }

    private func showCurrentInFiles() {
        if let path = currentItem?.filePath {
            richActions?.openFile(path)
        }
    }

    private func copyCurrentImage() {
        if let currentImage {
            if let richActions {
                richActions.copyImage(currentImage)
            } else {
                UIPasteboard.general.image = currentImage
                Haptics.light()
            }
        } else if case .remote(let url) = currentItem?.fullSource {
            // Nothing decoded yet: the link is all we honestly have.
            if let richActions {
                richActions.copyText(url.absoluteString)
            } else {
                UIPasteboard.general.string = url.absoluteString
                Haptics.light()
            }
        }
    }

    /// The composer attachment path (M6a): JPEG-encode off main, then hand the bytes to the
    /// tray, which decodes and uploads like a picked photo. The `UIImage` crossing uses
    /// the same `@unchecked Sendable` box the pipeline uses (immutable once decoded).
    private func addCurrentToChat() {
        guard let currentImage, let item = currentItem else { return }
        let fileName = item.fileName
        Task { @MainActor in
            let data = await Task.detached(priority: .userInitiated) {
                ImageBox(image: currentImage).image.jpegData(compressionQuality: 0.85)
            }.value
            guard let data else { return }
            if let richActions {
                richActions.addImageToChat(fileName, data)
            }
        }
    }

    private struct ImageBox: @unchecked Sendable {
        let image: UIImage
    }
}
#endif
