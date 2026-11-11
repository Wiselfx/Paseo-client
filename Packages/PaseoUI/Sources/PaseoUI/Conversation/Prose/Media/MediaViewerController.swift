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
            coordinator.parent.chromeVisible.toggle()
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
        view.backgroundColor = .black
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

/// One zooming page: the thumbnail instantly, the full image crossfaded in behind it.
///
/// Gestures, all UIKit (R-3):
/// - one-finger swipe: the pager (this page does not claim horizontal drags);
/// - pinch: 1× … max(4, full pixels / display points), centred where the fingers are;
/// - double-tap: 2.5× at the tap point, or back to fit;
/// - single tap: toggle the SwiftUI chrome;
/// - drag down at 1×: tracked here; release dismisses into a velocity-matched critically
///   damped spring (`UISpringTimingParameters(dampingRatio: 1)`), or springs home.
final class MediaViewerPageController: UIViewController {
    let item: MediaViewerItem
    private let reduceMotion: Bool
    private let onToggleChrome: () -> Void
    private let onImage: (UIImage?) -> Void
    private let onLiveText: (Bool) -> Void
    private let onClose: () -> Void

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    /// VisionKit Live Text, attached once the full image lands (G3 §4.6).
    private var textInteraction: ImageAnalysisInteraction?
    private var analyzerTask: Task<Void, Never>?

    /// The sharpest bitmap this page holds: the full fetch, the animated frames, or the
    /// thumbnail when the source needs no fetch.
    private(set) var displayedImage: UIImage?
    /// Whether the last analysis found text (reported once per page).
    private(set) var liveTextFound = false

    private var fullTask: Task<Void, Never>?
    private var dismissPan: UIPanGestureRecognizer?

    init(
        item: MediaViewerItem, reduceMotion: Bool,
        onToggleChrome: @escaping () -> Void,
        onImage: @escaping (UIImage?) -> Void,
        onLiveText: @escaping (Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.item = item
        self.reduceMotion = reduceMotion
        self.onToggleChrome = onToggleChrome
        self.onImage = onImage
        self.onLiveText = onLiveText
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureScrollView()
        configureGestures()
        if let thumbnail = item.thumbnail {
            setImage(thumbnail, animated: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The window (and its screen scale) exists only once presented: the full fetch
        // waits for it, so zoom starts at true display pixels instead of a fallback.
        if fullTask == nil {
            startFullFetch(scaleOverride: nil)
        }
    }

    /// Warms a neighbour before the swipe (±1 preloaded, G3 §4.6): its view may never load,
    /// so this cannot wait for `viewDidAppear` — the 3× fallback scale is exact on most
    /// iPhones and a harmless over-decode elsewhere (capped by the 3072 side bound).
    func preloadFull() {
        if fullTask == nil {
            startFullFetch(scaleOverride: 3)
        }
    }

    deinit {
        fullTask?.cancel()
        analyzerTask?.cancel()
    }

    // MARK: Image

    private func configureScrollView() {
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        // At 1× the content cannot scroll, so the scroll view must not bounce under the
        // dismiss pan — the two would add. Zoomed pages keep their edge bounce.
        scrollView.bounces = false
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        view.addSubview(scrollView)
    }

    private func configureGestures() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        pan.delegate = self
        imageView.addGestureRecognizer(doubleTap)
        imageView.addGestureRecognizer(singleTap)
        scrollView.addGestureRecognizer(pan)
        dismissPan = pan
    }

    @objc
    private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        onToggleChrome()
    }

    @objc
    private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard displayedImage != nil else { return }
        if scrollView.zoomScale > 1.5 {
            scrollView.setZoomScale(1, animated: !reduceMotion)
        } else {
            let point = recognizer.location(in: imageView)
            let zoom: CGFloat = 2.5
            let size = CGSize(
                width: scrollView.bounds.width / zoom, height: scrollView.bounds.height / zoom)
            scrollView.zoom(
                to: CGRect(
                    x: point.x - size.width / 2, y: point.y - size.height / 2,
                    width: size.width, height: size.height),
                animated: !reduceMotion)
        }
    }

    /// Full resolution on open, off main; neighbours ±1 preload because the pager builds
    /// them before the swipe. A still source (`fullSource == nil`) skips the fetch: the
    /// thumbnail *is* the full image.
    private func startFullFetch(scaleOverride: CGFloat? = nil) {
        guard let source = item.fullSource else {
            onImage(item.thumbnail)
            return
        }
        fullTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let pixels = self.fullPixelWidth(scaleOverride: scaleOverride)
            let outcome = await MediaPipeline.shared.load(
                source: source, pixelWidth: pixels, maxSide: 3072, cacheResult: false)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .image(let payload):
                if payload.isAnimated, let data = payload.fullData {
                    self.setAnimatedImage(data: data)
                } else {
                    self.setImage(payload.image, animated: !self.reduceMotion)
                }
                self.startTextAnalysis(image: payload.image)
            case .svg, .failure:
                // The thumbnail (or nothing) stands: a failed full fetch never empties the page.
                self.onImage(self.displayedImage)
            }
        }
    }

    /// The decode width for the full image: the display pixels, so zoom starts sharp. Capped
    /// by the pipeline's 3072 side bound (~36 MB transient, released with the page).
    private func fullPixelWidth(scaleOverride: CGFloat? = nil) -> Int {
        let scale = scaleOverride ?? view.window?.screen.scale ?? 2
        let width = max(view.bounds.width, 1) * scale
        return MediaSizing.pixelWidth(points: width, scale: 1)
    }

    private func setImage(_ image: UIImage, animated: Bool) {
        displayedImage = image
        layoutImage()
        updateMaxZoom(for: image)
        if animated {
            imageView.alpha = 0
            imageView.image = image
            UIView.animate(withDuration: 0.2) { self.imageView.alpha = 1 }
        } else {
            imageView.image = image
        }
        onImage(image)
    }

    private func setAnimatedImage(data: Data) {
        let width = max(scrollView.bounds.width, 1)
            * (view.window?.screen.scale ?? 2)
        Task.detached(priority: .userInitiated) { [weak self] in
            let animated = AnimatedImageDecoder.animatedImage(data: data, pixelWidth: width)
            await MainActor.run { [weak self] in
                guard let self, let animated else { return }
                self.setImage(animated, animated: !self.reduceMotion)
                self.startTextAnalysis(image: animated)
            }
        }
    }

    /// VisionKit Live Text (G3 §4.6): the analysis runs once per page, off main. The button
    /// appears only when text is found; it toggles the selection UI.
    private func startTextAnalysis(image: UIImage) {
        analyzerTask?.cancel()
        analyzerTask = Task.detached(priority: .utility) { [weak self] in
            let analyzer = ImageAnalyzer()
            let analysis: ImageAnalysis?
            do {
                analysis = try await analyzer.analyze(image, orientation: .up)
            } catch {
                analysis = nil
            }
            // The decoded bitmaps already carry EXIF orientation, so `.up` is exact.
            let found = !(analysis?.transcript.isEmpty ?? true)
            await MainActor.run { [weak self] in
                guard let self, let analysis, found else { return }
                if self.textInteraction == nil {
                    let interaction = ImageAnalysisInteraction()
                    interaction.preferredInteractionTypes = .automatic
                    self.imageView.addInteraction(interaction)
                    self.textInteraction = interaction
                }
                self.textInteraction?.analysis = analysis
                self.liveTextFound = true
                self.onLiveText(true)
            }
        }
    }

    func setLiveTextMode(_ mode: Bool) {
        textInteraction?.preferredInteractionTypes = mode ? .automatic : []
    }

    private func updateMaxZoom(for image: UIImage) {
        let fitWidth = max(imageView.frame.width, 1)
        let pixels = max(image.size.width * image.scale, 1)
        scrollView.maximumZoomScale = max(4, pixels / fitWidth)
    }

    // MARK: Dismiss (R-3)

    @objc
    private func handleDismissPan(_ recognizer: UIPanGestureRecognizer) {
        // Zoomed content pans; only a 1× page dismisses.
        guard scrollView.zoomScale <= 1.01 else { return }
        let translation = recognizer.translation(in: view)
        let velocity = recognizer.velocity(in: view)
        switch recognizer.state {
        case .changed:
            let dy = translation.y > 0 ? translation.y : translation.y / 3
            scrollView.transform = CGAffineTransform(translationX: 0, y: dy)
            scrollView.alpha = 1 - min(max(translation.y, 0) / (view.bounds.height * 0.5), 0.6)
        case .ended, .cancelled:
            let distance = translation.y
            if recognizer.state == .ended
                && (distance > 120 || velocity.y > 800)
            {
                dismissWithVelocity(velocity)
            } else {
                springHome(velocity: velocity)
            }
        default:
            break
        }
    }

    /// Release into a velocity-matched critically damped spring, then close. The content is
    /// already gone when the cover dismisses, so no transition ever jumps.
    private func dismissWithVelocity(_ velocity: CGPoint) {
        let timing = UISpringTimingParameters(
            dampingRatio: 1,
            initialVelocity: CGVector(dx: velocity.x / 1000, dy: velocity.y / 1000))
        let animator = UIViewPropertyAnimator(duration: 0.25, timingParameters: timing)
        animator.addAnimations {
            self.scrollView.transform = CGAffineTransform(
                translationX: 0, y: self.view.bounds.height)
            self.scrollView.alpha = 0
        }
        animator.addCompletion { _ in self.onClose() }
        animator.startAnimation()
    }

    private func springHome(velocity: CGPoint) {
        let timing = UISpringTimingParameters(
            dampingRatio: 1,
            initialVelocity: CGVector(dx: velocity.x / 1000, dy: velocity.y / 1000))
        let animator = UIViewPropertyAnimator(duration: 0.32, timingParameters: timing)
        animator.addAnimations {
            self.scrollView.transform = .identity
            self.scrollView.alpha = 1
        }
        animator.startAnimation()
    }
}

extension MediaViewerPageController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        scrollView.bounces = scrollView.zoomScale > 1.01
        centreImage()
    }

    /// Keeps a sub-screen image centred while zooming; a taller image scrolls.
    private func centreImage() {
        let horizontal = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
        let vertical = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
        imageView.frame.origin = CGPoint(
            x: scrollView.contentSize.width < scrollView.bounds.width
                ? horizontal : imageView.frame.origin.x,
            y: scrollView.contentSize.height < scrollView.bounds.height
                ? vertical : imageView.frame.origin.y)
    }
}

extension MediaViewerPageController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // The dismiss pan owns 1× pages; zoomed content pans inside the scroll view.
        guard let pan = dismissPan, gestureRecognizer === pan else { return true }
        return scrollView.zoomScale <= 1.01
    }
}

extension MediaViewerPageController {
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutImage()
    }

    /// The fitted frame: aspect-fit in the scroll view, never upscaled past it.
    private func layoutImage() {
        guard let image = displayedImage ?? item.thumbnail else { return }
        let bounds = scrollView.bounds.size
        guard bounds.width > 1, bounds.height > 1 else { return }
        let aspect = image.size.width / max(image.size.height, 1)
        var width = bounds.width
        var height = width / aspect
        if height > bounds.height {
            height = bounds.height
            width = height * aspect
        }
        imageView.frame = CGRect(
            x: max((bounds.width - width) / 2, 0),
            y: max((bounds.height - height) / 2, 0),
            width: max(width, 1), height: max(height, 1))
        scrollView.contentSize = imageView.frame.size
        if let displayed = displayedImage {
            updateMaxZoom(for: displayed)
        }
    }
}
#endif
