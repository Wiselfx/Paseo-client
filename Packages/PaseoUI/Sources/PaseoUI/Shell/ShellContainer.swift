#if canImport(UIKit)
import SwiftUI
import UIKit

/// The UIKit drawer container (R5 §1): three hosting controllers, one pan recognizer, one
/// animator. SwiftUI hands it the three roots and never sees a progress value, so a drag writes
/// `transform` and `alpha` on the layer tree and evaluates no body.
struct ShellContainer: UIViewControllerRepresentable {
    let drawer: ShellDrawer
    let sidebar: AnyView
    let main: AnyView
    let panel: AnyView

    func makeUIViewController(context: Context) -> ShellContainerController {
        let controller = ShellContainerController(drawer: drawer)
        controller.setRoots(sidebar: sidebar, main: main, panel: panel)
        return controller
    }

    func updateUIViewController(_ controller: ShellContainerController, context: Context) {
        controller.setRoots(sidebar: sidebar, main: main, panel: panel)
    }
}

/// The shell's one moving part.
///
/// The sidebar sits at the bottom and never moves; the conversation card slides right over it; the
/// panel card slides in from the right over both. Every move is one `UIViewPropertyAnimator` with
/// a critically damped spring, seeded with the finger's velocity, and a pan that starts during a
/// settle grabs the surface where it is (R5 §1–§3).
@MainActor
final class ShellContainerController: UIViewController, UIGestureRecognizerDelegate {
    private let drawer: ShellDrawer

    private let sidebarHost = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
    private let conversationHost = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
    private let panelHost = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
    private let conversationCard = ShellCardView(frame: .zero)
    private let panelCard = ShellCardView(frame: .zero)
    private let dimView = UIView()
    private let drawerPan = UIPanGestureRecognizer()

    /// The three roots exactly as SwiftUI built them; the container wraps them with the
    /// environment values it owns and never rebuilds them for a progress change (R5 §1).
    private var sidebarRoot: AnyView = AnyView(EmptyView())
    private var mainRoot: AnyView = AnyView(EmptyView())
    private var panelRoot: AnyView = AnyView(EmptyView())
    private var rootsChanged = true
    private var mainObscured = false
    private var sidebarObscured = true
    private var panelVisible = false
    private var panelObscured = true
    private var appliedMainObscured: Bool?
    private var appliedSidebarObscured: Bool?
    private var appliedPanelVisible: Bool?
    private var appliedPanelObscured: Bool?

    /// Model progress, 0…1. Written per frame while tracking, animated once per settle.
    private var sidebarProgress: CGFloat = 0
    private var panelProgress: CGFloat = 0
    private var animator: UIViewPropertyAnimator?
    /// The surface the pan in flight drives; nil between gestures.
    private var activeSurface: ShellDrawer.Surface?
    private var panOrigin: CGFloat = 0
    private var panStart: CGPoint = .zero

    init(drawer: ShellDrawer) {
        self.drawer = drawer
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    // MARK: Geometry

    private var width: CGFloat { max(view.bounds.width, 1) }
    private var drawerWidth: CGFloat { (width * 0.82).rounded() }
    private var parallax: CGFloat { width * 0.3 }
    private var isDark: Bool { traitCollection.userInterfaceStyle == .dark }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // The sidebar sits on the container's canvas (OCU §12.4).
        view.backgroundColor = UIColor(Palette.sidebar)
        view.insetsLayoutMarginsFromSafeArea = false
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true

        addChild(sidebarHost)
        sidebarHost.view.backgroundColor = .clear
        view.addSubview(sidebarHost.view)
        sidebarHost.didMove(toParent: self)

        addChild(conversationHost)
        conversationHost.view.backgroundColor = .clear
        conversationCard.addSubview(conversationHost.view)
        conversationHost.didMove(toParent: self)

        dimView.backgroundColor = .black
        dimView.alpha = 0
        dimView.isUserInteractionEnabled = false
        dimView.isAccessibilityElement = false
        dimView.accessibilityLabel = "Close"
        dimView.accessibilityTraits = .button
        dimView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(closeSurface)))
        conversationCard.addSubview(dimView)

        addChild(panelHost)
        panelHost.view.backgroundColor = .clear
        panelCard.addSubview(panelHost.view)
        panelHost.didMove(toParent: self)

        view.addSubview(conversationCard)
        view.addSubview(panelCard)

        drawerPan.addTarget(self, action: #selector(handlePan))
        drawerPan.delegate = self
        drawerPan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(drawerPan)

        drawer.controller = self
        applyColors()
        applyChrome()

        _ = registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (controller: ShellContainerController, _: UITraitCollection) in
            controller.applyColors()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The key commands hang off this controller; nothing else is first responder when the
        // shell appears, and a focused field later keeps working because it inherits the chain.
        if !isFirstResponder { becomeFirstResponder() }
    }

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layout(card: conversationCard, hosting: conversationHost)
        layout(card: panelCard, hosting: panelHost)
        // The sidebar lays out at the width the drawer reveals, not at the screen's width: at full
        // width its rows ran under the conversation card and the New session pill was cut off
        // (D3 §1).
        sidebarHost.view.frame = CGRect(
            x: 0, y: 0, width: drawerWidth, height: view.bounds.height)
        dimView.frame = conversationCard.bounds
        // Rotation and first layout: the state is unchanged, the geometry is not.
        writeModel(sidebar: sidebarProgress, panel: panelProgress)
    }

    private func layout(card: ShellCardView, hosting: UIHostingController<AnyView>) {
        card.bounds = CGRect(origin: .zero, size: view.bounds.size)
        card.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        hosting.view.frame = card.bounds
        card.updateHairlinePath()
    }

    // MARK: Model

    private func applyColors() {
        conversationCard.applyColors(in: traitCollection)
        panelCard.applyColors(in: traitCollection)
        writeModel(sidebar: sidebarProgress, panel: panelProgress)
    }

    /// The one place that writes the four moving values. Called inside an animator's animation
    /// block for a settle, and with actions disabled while a finger drives it.
    private func applyModel(sidebar s: CGFloat, panel p: CGFloat) {
        conversationCard.transform = CGAffineTransform(
            translationX: drawerWidth * s - parallax * p, y: 0)
        panelCard.transform = CGAffineTransform(translationX: width * (1 - p), y: 0)
        dimView.alpha = CGFloat(EdgeDrawer.scrimOpacity(max(s, p), dark: isDark))
        conversationCard.hairlineOpacity = Float(s)
        panelCard.hairlineOpacity = Float(p)
    }

    private func writeModel(sidebar s: CGFloat, panel p: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation { applyModel(sidebar: s, panel: p) }
        CATransaction.commit()
    }

    private func setProgress(_ value: CGFloat, for surface: ShellDrawer.Surface) {
        let clamped = min(max(value, 0), 1)
        switch surface {
        case .sidebar: sidebarProgress = clamped
        case .panel: panelProgress = clamped
        case .none: break
        }
    }

    // MARK: Committed state

    private func applyChrome() {
        let open = drawer.state
        conversationCard.accessibilityElementsHidden = open != .none
        sidebarHost.view.accessibilityElementsHidden = open != .sidebar
        panelCard.isHidden = panelProgress == 0
        panelCard.accessibilityElementsHidden = panelProgress == 0
        panelCard.isUserInteractionEnabled = panelProgress > 0
        let interactive = max(sidebarProgress, panelProgress) > 0
        dimView.isUserInteractionEnabled = interactive
        dimView.isAccessibilityElement = interactive

        mainObscured = open != .none
        sidebarObscured = open != .sidebar
        panelVisible = panelProgress > 0
        panelObscured = panelProgress == 0
        applyRoots()
    }

    /// Flips `\.isSurfaceObscured` / `\.isPanelVisible` at the start and end of a motion only.
    private func beginMotion(target: ShellDrawer.Surface) {
        // The panel mounts its page on this flip, so a closed panel that is only sliding the
        // sidebar never mounts anything (P5-D).
        let panelOnScreen = target == .panel || panelProgress > 0
        if panelOnScreen {
            panelCard.isHidden = false
            panelCard.isUserInteractionEnabled = true
        }
        dimView.isUserInteractionEnabled = true
        dimView.isAccessibilityElement = true

        mainObscured = true
        sidebarObscured = false
        panelVisible = panelOnScreen
        panelObscured = !panelOnScreen
        applyRoots()
    }

    private func commit(_ target: ShellDrawer.Surface) {
        let changed = drawer.state != target
        drawer.adopt(target)
        if changed {
            Haptics.selection()
            if target == .sidebar { view.endEditing(true) }
        }
        applyChrome()
        if changed { drawer.onStateChange?(target) }
    }

    private func applyRoots() {
        let flagsChanged =
            appliedMainObscured != mainObscured
            || appliedSidebarObscured != sidebarObscured
            || appliedPanelVisible != panelVisible
            || appliedPanelObscured != panelObscured
        guard flagsChanged || rootsChanged else { return }
        rootsChanged = false
        appliedMainObscured = mainObscured
        appliedSidebarObscured = sidebarObscured
        appliedPanelVisible = panelVisible
        appliedPanelObscured = panelObscured

        sidebarHost.rootView = AnyView(
            sidebarRoot.environment(\.isSurfaceObscured, sidebarObscured))
        conversationHost.rootView = AnyView(
            mainRoot.environment(\.isSurfaceObscured, mainObscured))
        panelHost.rootView = AnyView(
            panelRoot
                .environment(\.isSurfaceObscured, panelObscured)
                .environment(\.isPanelVisible, panelVisible))
    }

    func setRoots(sidebar: AnyView, main: AnyView, panel: AnyView) {
        sidebarRoot = sidebar
        mainRoot = main
        panelRoot = panel
        rootsChanged = true
        applyRoots()
    }

    // MARK: Motion

    /// Programmatic: the same animator with no finger speed (R5 §3).
    func animate(to target: ShellDrawer.Surface) {
        if target == drawer.state, animator == nil, activeSurface == nil { return }
        runMotion(to: target, velocity: 0)
    }

    private func runMotion(to target: ShellDrawer.Surface, velocity: CGFloat) {
        animator?.stopAnimation(true)
        animator = nil

        let driven: ShellDrawer.Surface =
            target == .none ? (activeSurface ?? drawer.state) : target
        let distance = driven == .panel ? width : drawerWidth
        let progress = driven == .panel ? panelProgress : sidebarProgress
        let targetProgress: CGFloat = target == driven ? 1 : 0
        let remaining = (targetProgress - progress) * distance

        let s: CGFloat = target == .sidebar ? 1 : 0
        let p: CGFloat = target == .panel ? 1 : 0
        let animator = makeAnimator(velocity: velocity, remaining: remaining)
        animator.addAnimations { [weak self] in
            guard let self else { return }
            self.sidebarProgress = s
            self.panelProgress = p
            self.applyModel(sidebar: s, panel: p)
        }
        animator.addCompletion { [weak self] position in
            guard let self else { return }
            if position == .end { self.commit(target) }
            if self.animator === animator { self.animator = nil }
        }
        self.animator = animator
        beginMotion(target: target)
        animator.startAnimation()
    }

    private func makeAnimator(velocity: CGFloat, remaining: CGFloat) -> UIViewPropertyAnimator {
        guard !UIAccessibility.isReduceMotionEnabled else {
            return UIViewPropertyAnimator(duration: 0.2, curve: .easeOut)
        }
        // The finger's speed, as a fraction of the distance still to travel.
        let relative = abs(remaining) >= 1 ? velocity / remaining : 0
        return UIViewPropertyAnimator(
            duration: 0.32,
            timingParameters: UISpringTimingParameters(
                dampingRatio: 1, initialVelocity: CGVector(dx: relative, dy: 0)))
    }

    /// A pan that starts during a settle stops the surface dead where it is and keeps tracking.
    private func interruptMotion() {
        guard let animator, animator.isRunning else { return }
        let conversationX =
            conversationCard.layer.presentation()?.transform.m41
            ?? conversationCard.layer.transform.m41
        let panelX =
            panelCard.layer.presentation()?.transform.m41
            ?? panelCard.layer.transform.m41
        animator.stopAnimation(true)
        self.animator = nil
        panelProgress = min(max(1 - panelX / max(1, width), 0), 1)
        sidebarProgress = min(
            max((conversationX + parallax * panelProgress) / max(1, drawerWidth), 0), 1)
        writeModel(sidebar: sidebarProgress, panel: panelProgress)
    }

    // MARK: Gestures

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            interruptMotion()
            guard let surface = activeSurface else { return }
            beginMotion(target: surface)
            panOrigin = surface == .panel ? panelProgress : sidebarProgress
            Haptics.prepare()
            if surface == .sidebar, drawer.state != .sidebar { view.endEditing(true) }
        case .changed:
            guard let surface = activeSurface else { return }
            let translation = gesture.translation(in: view).x
            let signed = surface == .panel ? -translation : translation
            let distance = surface == .panel ? width : drawerWidth
            setProgress(panOrigin + signed / max(1, distance), for: surface)
            writeModel(sidebar: sidebarProgress, panel: panelProgress)
        case .ended, .cancelled, .failed:
            guard let surface = activeSurface else { return }
            settle(surface: surface, velocity: gesture.velocity(in: view).x,
                   cancelled: gesture.state != .ended)
        default:
            break
        }
    }

    private func settle(surface: ShellDrawer.Surface, velocity: CGFloat, cancelled: Bool) {
        let signed = cancelled ? 0 : (surface == .panel ? -velocity : velocity)
        let distance = surface == .panel ? width : drawerWidth
        let progress = surface == .panel ? panelProgress : sidebarProgress
        // UIKit's deceleration projection (WWDC18): v * 0.998 / (1 - 0.998) / 1000.
        let projectedPoints = signed / 1000 * 0.998 / (1 - 0.998)
        let projected = progress + projectedPoints / max(1, distance)
        let opens = !cancelled && projected >= 0.5
        runMotion(to: opens ? surface : .none, velocity: signed)
        activeSurface = nil
    }

    private func horizontallyScrollable(_ scrollView: UIScrollView) -> Bool {
        scrollView.isScrollEnabled && scrollView.contentSize.width > scrollView.bounds.width + 1
    }

    /// The touch's own view, or one of its ancestors: a horizontally scrollable scroll view, or
    /// text that is being edited, owns the gesture instead.
    private func isBlocked(at point: CGPoint) -> Bool {
        guard let hit = view.hitTest(point, with: nil) else { return false }
        var node: UIView? = hit
        while let current = node, current !== view {
            if let scrollView = current as? UIScrollView, horizontallyScrollable(scrollView) {
                return true
            }
            if current is UITextInput, current.isFirstResponder { return true }
            node = current.superview
        }
        return false
    }

    private func card(at point: CGPoint) -> UIView {
        panelCard.frame.contains(point) ? panelCard : conversationCard
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === drawerPan,
            let pan = gestureRecognizer as? UIPanGestureRecognizer
        else { return true }
        let velocity = pan.velocity(in: view)
        let start = pan.location(in: view)
        guard abs(velocity.x) > abs(velocity.y) * 1.2, velocity.x != 0 else { return false }
        guard !isBlocked(at: start) else { return false }

        let driving: ShellDrawer.Surface
        switch drawer.state {
        case .none:
            if velocity.x > 0 {
                // The trailing strip belongs to the turn rail when it is on screen.
                if drawer.trailingEdgeReserved, start.x > width - EdgeDrawer.edgeZone {
                    return false
                }
                driving = .sidebar
            } else {
                guard start.x > width - EdgeDrawer.edgeZone,
                    !drawer.trailingEdgeReserved
                else { return false }
                driving = .panel
            }
        case .sidebar:
            guard velocity.x < 0 else { return false }
            driving = .sidebar
        case .panel:
            guard velocity.x > 0, !drawer.panelHandlesBack,
                panelCard.frame.contains(start)
            else { return false }
            driving = .panel
        }
        activeSurface = driving
        panStart = start
        return true
    }

    /// Vertical scrolling waits for `drawerPan` to fail, and it fails at its first movement when
    /// the movement is not horizontal, so scrolls keep their own timing (R5 §3).
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === drawerPan,
            let scrollView = otherGestureRecognizer.view as? UIScrollView,
            scrollView.panGestureRecognizer === otherGestureRecognizer,
            scrollView.isDescendant(of: card(at: panStart))
        else { return false }
        return !horizontallyScrollable(scrollView)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    // MARK: Closing

    @objc private func closeSurface() {
        drawer.close()
    }

    override func accessibilityPerformEscape() -> Bool {
        guard drawer.state != .none else { return false }
        drawer.close()
        return true
    }

    // MARK: Keyboard

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                title: "Search", action: #selector(searchCommand), input: "k",
                modifierFlags: .command),
            UIKeyCommand(
                title: "New session", action: #selector(newSessionCommand), input: "n",
                modifierFlags: .command),
            UIKeyCommand(
                title: "Show sidebar", action: #selector(toggleSidebarCommand), input: "\\",
                modifierFlags: .command),
            UIKeyCommand(
                title: "Show workspace", action: #selector(togglePanelCommand), input: "\\",
                modifierFlags: [.command, .shift]),
            UIKeyCommand(
                input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapeCommand)),
        ]
    }

    @objc private func searchCommand() {
        drawer.onSearch?()
    }

    @objc private func newSessionCommand() {
        drawer.onNewSession?()
    }

    @objc private func toggleSidebarCommand() {
        drawer.toggle(.sidebar)
    }

    @objc private func togglePanelCommand() {
        drawer.toggle(.panel)
    }

    @objc private func escapeCommand() {
        drawer.close()
    }
}

/// One drawer surface: the display's corner shape, its own canvas, and a hairline that fades with
/// progress instead of a border that cannot (R5 §2).
@MainActor
final class ShellCardView: UIView {
    private let hairline = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = EdgeDrawer.cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        hairline.fillColor = nil
        hairline.lineWidth = 0.5
        hairline.opacity = 0
        layer.addSublayer(hairline)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    var hairlineOpacity: Float {
        get { hairline.opacity }
        set { hairline.opacity = newValue }
    }

    func applyColors(in traits: UITraitCollection) {
        // Resolved against the card's own traits: a layer's `cgColor` is a snapshot, so dark and
        // pure black are read again on every trait change.
        backgroundColor = UIColor(Palette.background).resolvedColor(with: traits)
        hairline.strokeColor = UIColor(Palette.ink)
            .withAlphaComponent(0.1)
            .resolvedColor(with: traits)
            .cgColor
    }

    func updateHairlinePath() {
        let inset = bounds.insetBy(dx: 0.25, dy: 0.25)
        guard inset.width > 0, inset.height > 0 else { return }
        hairline.path = Path(
            roundedRect: inset, cornerRadius: EdgeDrawer.cornerRadius, style: .continuous
        ).cgPath
    }
}
#endif
