#if canImport(UIKit)
import SwiftUI
import UIKit
import VisionKit

// MARK: - MediaViewerController (G3 §4.6, R-3)

// NOTE: RemoteImagePipeline/G3: every finger-tracked surface here is UIKit. SwiftUI hosts
// this pager plus the chrome and learns only open/closed, the page index and the few values
// the chrome draws. Nothing scrolls, zooms or dismisses through a SwiftUI gesture.

/// The representable: a `UIPageViewController` of zooming `UIScrollView` pages. The pager
/// owns the pages and the gestures; the coordinator ferries index/image/Live Text state
/// back to the SwiftUI chrome through bindings (written on the main actor only).
struct MediaViewerPager: UIViewControllerRepresentable {
    let items: [MediaViewerItem]
    @Binding var selection: Int
    @Binding var chromeVisible: Bool
    @Binding var currentImage: UIImage?
    @Binding var liveTextAvailable: Bool
    var liveTextMode: Bool
    let onClose: () -> Void
    var reduceMotion = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> MediaViewerPagerController {
        let pager = MediaViewerPagerController(
            items: items,
            startIndex: min(max(selection, 0), max(items.count - 1, 0)),
            reduceMotion: reduceMotion)
        pager.onIndexChange = { [weak coordinator = context.coordinator] index in
            coordinator?.parent.selection = index
        }
        pager.onToggleChrome = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return }
            // Fade, don't pop: the chrome is one element appearing and leaving.
            withAnimation(
                Motion.fade.resolved(reduceMotion: coordinator.parent.reduceMotion)
            ) {
                coordinator.parent.chromeVisible.toggle()
            }
        }
        pager.onCurrentImage = { [weak coordinator = context.coordinator] image in
            coordinator?.parent.currentImage = image
        }
        pager.onLiveText = { [weak coordinator = context.coordinator] available in
            coordinator?.parent.liveTextAvailable = available
        }
        pager.onClose = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onClose()
        }
        context.coordinator.pager = pager
        return pager
    }

    func updateUIViewController(_ pager: MediaViewerPagerController, context: Context) {
        // The struct copy the coordinator closes over goes stale (bindings do not); refresh
        // it so callbacks read the current closures.
        context.coordinator.parent = self
        pager.isChromeVisible = chromeVisible
        pager.setLiveTextMode(liveTextMode)
    }

    final class Coordinator: NSObject {
        var parent: MediaViewerPager
        weak var pager: MediaViewerPagerController?

        init(_ parent: MediaViewerPager) {
            self.parent = parent
        }
    }
}
#endif
