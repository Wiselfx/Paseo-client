#if canImport(UIKit)
import SwiftUI
import UIKit
import VisionKit

/// One UIPageViewController for the whole viewer: swipe between pages, with the current
/// page's zooming scroll view inside. Black canvas; the SwiftUI chrome floats above.
final class MediaViewerPagerController: UIPageViewController {
    private let items: [MediaViewerItem]
    private let reduceMotion: Bool
    private var currentIndex: Int
    /// The three live pages around the reader (current ± 1 preloaded, the rest released).
    private var pages: [Int: MediaViewerPageController] = [:]

    var onIndexChange: ((Int) -> Void)?
    var onToggleChrome: (() -> Void)?
    var onCurrentImage: ((UIImage?) -> Void)?
    var onLiveText: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    var isChromeVisible = true {
        didSet {
            guard isChromeVisible != oldValue else { return }
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    /// Reduce Motion renders the pager without the inter-page slide.
    override var prefersStatusBarHidden: Bool { !isChromeVisible }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    /// The black behind the pages, faded by the dismiss drag (the SwiftUI cover behind
    /// is clear, so the transcript shows through as the image leaves).
    private let dimView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }()

    init(items: [MediaViewerItem], startIndex: Int, reduceMotion: Bool) {
        self.items = items
        self.currentIndex = startIndex
        self.reduceMotion = reduceMotion
        super.init(
            transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The window style stays dark even in a light transcript.
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .clear
        dimView.frame = view.bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(dimView, at: 0)
        dataSource = self
        delegate = self
        if let first = page(for: currentIndex) {
            setViewControllers([first], direction: .forward, animated: false)
            publishCurrent()
        }
    }

    /// The page for an index, built once and kept while adjacent. Distant pages are released
    /// with their full-resolution bitmaps; scrolling back rebuilds from the thumbnail.
    private func page(for index: Int) -> MediaViewerPageController? {
        guard items.indices.contains(index) else { return nil }
        if let cached = pages[index] { return cached }
        // Built pages start their full fetch even before display: the pager builds the
        // neighbourhood ahead of the swipe (±1 preloaded, G3 §4.6).
        let page = MediaViewerPageController(
            item: items[index], reduceMotion: reduceMotion,
            onToggleChrome: { [weak self] in self?.onToggleChrome?() },
            onImage: { [weak self] image in
                guard let self, self.currentIndex == index else { return }
                self.onCurrentImage?(image)
            },
            onLiveText: { [weak self] available in
                guard let self, self.currentIndex == index else { return }
                self.onLiveText?(available)
            },
            onClose: { [weak self] in self?.onClose?() })
        pages[index] = page
        page.backdrop = dimView
        // The displayed page loads in `viewDidAppear` at the exact screen scale; only
        // neighbours preload with the fallback scale.
        if index != currentIndex {
            page.preloadFull()
        }
        // Only the neighbourhood lives: a 3072 px bitmap per page is ~36 MB.
        for key in pages.keys where abs(key - currentIndex) > 1 {
            pages.removeValue(forKey: key)
        }
        return page
    }

    private func publishCurrent() {
        onIndexChange?(currentIndex)
        if let page = pages[currentIndex] {
            onCurrentImage?(page.displayedImage)
            onLiveText?(page.liveTextFound)
        } else {
            onCurrentImage?(items[currentIndex].thumbnail)
            onLiveText?(false)
        }
    }

    func setLiveTextMode(_ mode: Bool) {
        pages[currentIndex]?.setLiveTextMode(mode)
    }
}
extension MediaViewerPagerController: UIPageViewControllerDataSource {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? MediaViewerPageController,
            let index = items.firstIndex(where: { $0.id == page.item.id })
        else { return nil }
        return self.page(for: index - 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? MediaViewerPageController,
            let index = items.firstIndex(where: { $0.id == page.item.id })
        else { return nil }
        return self.page(for: index + 1)
    }
}
extension MediaViewerPagerController: UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
            let page = pageViewController.viewControllers?.first
                as? MediaViewerPageController,
            let index = items.firstIndex(where: { $0.id == page.item.id })
        else { return }
        currentIndex = index
        // Warm the new neighbourhood: building the page starts its full fetch off main.
        _ = self.page(for: index - 1)
        _ = self.page(for: index + 1)
        publishCurrent()
    }
}
#endif
