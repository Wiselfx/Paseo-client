#if canImport(UIKit)
import SwiftTerm
import SwiftUI
import UIKit

/// A virtual key bar shown above the keyboard while a terminal is focused: the keys the
/// iOS software keyboard can't produce — Esc, Tab, a sticky one-shot Ctrl, arrows, and the
/// shell punctuation `|`, `~`, `/`, `-` — plus a hide/show-keyboard button.
///
/// Wired to SwiftTerm's `TerminalView` as `inputAccessoryView` (the built-in accessory is
/// replaced). Arrow keys go through `TerminalView.sendKeyUp/Down/Left/Right`, which encode
/// for the app's cursor-key mode. Esc/Tab/punctuation are sent as raw bytes through
/// `TerminalsStore.sendInput`. Ctrl flips `TerminalView.controlModifier`, which SwiftTerm
/// clears after the next key automatically.
///
/// The bar is a `.keyboard`-style input view with no fill of its own, so it carries the keyboard's
/// material and reads as part of it. Each key is a rounded translucent key (`TerminalKeyStyle`,
/// `KeyButton`), drawn at least 40 x 44 pt with a 44 pt wide touch area, in three groups: Esc, Tab,
/// Ctrl | arrows | the rest. The keys scroll sideways when they don't fit and Hide stays pinned at
/// the trailing edge.
///
/// Every key lights up on touch-down and acts when the finger lifts inside it, like the system
/// keyboard's keys, so a drag that turns into a scroll never types. That includes the arrows: an
/// arrow that fired on touch-down sent Up (a shell history recall) every time a scroll started on
/// it. Holding an arrow still repeats: after `repeatDelay` it fires and keeps firing until the
/// finger lifts, is cancelled by a scroll, or leaves the key; a lift after a repeat sends nothing
/// more.
final class PaseoTerminalKeyBar: UIInputView, UIInputViewAudioFeedback {
    private weak var terminalView: TerminalView?
    private let onInput: (String) -> Void
    private var ctrlButton: UIButton?
    /// The held arrow key's repeat: a delay, then a steady beat until the finger lifts.
    private var repeatTask: Task<Void, Never>?
    /// The held arrow has already fired from the hold, so the lift sends nothing more.
    private var holdDidFire = false
    /// Written once in init, read once in deinit (which is nonisolated).
    nonisolated(unsafe) private var resetObserver: NSObjectProtocol?
    /// The keys and Hide, swapped for the upload row while a transfer is in flight.
    private let keysArea = UIView()
    private let uploadRow = UIStackView()
    private let uploadFileLabel = UILabel()
    private let uploadProgress = UIProgressView(progressViewStyle: .default)

    private static let ink = UIColor(Palette.ink)
    /// The key titles' and the upload file name's base sizes, scaled with Dynamic Type up to
    /// `TerminalKeyStyle.maximumContentSize`.
    private static let keyTitleFontSize: CGFloat = 17
    private static let uploadFileFontSize: CGFloat = 12

    /// Set by the coordinator; invoked when the paperclip is tapped.
    var onAttach: (() -> Void)?
    /// Set by the coordinator; invoked when the upload row's cancel button is tapped.
    var onCancelUpload: (() -> Void)?

    init(terminalView: TerminalView, onInput: @escaping (String) -> Void) {
        self.terminalView = terminalView
        self.onInput = onInput
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: TerminalChrome.keyBarHeight),
            inputViewStyle: .keyboard)
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.flexibleWidth]
        // The bar's height is fixed, so past this size the glyphs and titles would overflow their
        // keys; the system keyboard stops growing its keys in the same way.
        maximumContentSizeCategory = TerminalKeyStyle.maximumContentSize

        let keys = UIStackView()
        keys.axis = .horizontal
        keys.distribution = .fill
        keys.alignment = .center
        keys.spacing = TerminalKeyStyle.keyGap
        keys.isLayoutMarginsRelativeArrangement = true
        keys.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0, leading: Space.sm, bottom: 0, trailing: Space.sm)
        keys.translatesAutoresizingMaskIntoConstraints = false

        // Group one: Esc, Tab, Ctrl.
        keys.addArrangedSubview(makeKey(image: "escape", label: "Escape") { [weak self] _ in
            self?.press("\u{1b}")
        })
        keys.addArrangedSubview(makeKey(image: "tab", label: "Tab") { [weak self] _ in
            self?.press("\t")
        })
        let ctrl = makeKey(image: "control", label: "Control", feedback: false) { [weak self] button in
            self?.toggleControl(button)
        }
        ctrl.accessibilityValue = String(localized: "Off", bundle: #bundle)
        ctrl.accessibilityHint = String(
            localized: "Applies Control to the next key you type.", bundle: #bundle)
        ctrlButton = ctrl
        keys.addArrangedSubview(ctrl)
        keys.setCustomSpacing(TerminalKeyStyle.groupGap, after: ctrl)
        // Group two: the arrows, which repeat while held.
        keys.addArrangedSubview(makeKey(image: "arrow.up", label: "Up arrow", repeats: true) { [weak self] _ in
            self?.terminalView?.sendKeyUp()
        })
        keys.addArrangedSubview(makeKey(image: "arrow.down", label: "Down arrow", repeats: true) { [weak self] _ in
            self?.terminalView?.sendKeyDown()
        })
        keys.addArrangedSubview(makeKey(image: "arrow.left", label: "Left arrow", repeats: true) { [weak self] _ in
            self?.terminalView?.sendKeyLeft()
        })
        let right = makeKey(image: "arrow.right", label: "Right arrow", repeats: true) { [weak self] _ in
            self?.terminalView?.sendKeyRight()
        }
        keys.addArrangedSubview(right)
        keys.setCustomSpacing(TerminalKeyStyle.groupGap, after: right)
        // Group three: shell punctuation and Attach.
        keys.addArrangedSubview(makeKey(title: "|", label: "Pipe") { [weak self] _ in self?.press("|") })
        keys.addArrangedSubview(makeKey(title: "~", label: "Tilde") { [weak self] _ in self?.press("~") })
        keys.addArrangedSubview(makeKey(title: "/", label: "Slash") { [weak self] _ in self?.press("/") })
        keys.addArrangedSubview(makeKey(title: "-", label: "Minus") { [weak self] _ in self?.press("-") })
        keys.addArrangedSubview(makeKey(image: "paperclip", label: "Attach a file") { [weak self] _ in
            self?.onAttach?()
        })
        // Hide stays put at the trailing edge, outside the scroller, so it is always reachable. The
        // glyph is the system's own "dismiss keyboard" symbol.
        let hide = makeKey(image: "keyboard.chevron.compact.down", label: "Hide keyboard") { [weak self] _ in
            self?.toggleKeyboard()
        }
        hide.widthAnchor.constraint(equalToConstant: TerminalChrome.hit).isActive = true

        let scroll = KeyBarScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(keys)
        keysArea.translatesAutoresizingMaskIntoConstraints = false
        keysArea.addSubview(scroll)
        keysArea.addSubview(hide)
        NSLayoutConstraint.activate([
            keys.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            keys.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            keys.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            keys.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            keys.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.leadingAnchor.constraint(equalTo: keysArea.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: keysArea.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: keysArea.bottomAnchor),
            scroll.trailingAnchor.constraint(
                equalTo: hide.leadingAnchor, constant: -TerminalKeyStyle.keyGap),
            hide.trailingAnchor.constraint(equalTo: keysArea.trailingAnchor, constant: -Space.sm),
            hide.centerYAnchor.constraint(equalTo: keysArea.centerYAnchor),
        ])

        // SwiftTerm resets controlModifier after the next key; keep the Ctrl button in sync.
        resetObserver = NotificationCenter.default.addObserver(
            forName: .terminalViewControlModifierReset, object: terminalView, queue: .main) { [weak self] _ in
            // Delivered on the main queue, so the main actor is already current.
            MainActor.assumeIsolated {
                if let ctrl = self?.ctrlButton { self?.showControl(ctrl, latched: false) }
            }
        }

        // The upload row replaces the keys while a T14 file transfer is in flight: spinner,
        // file name, byte progress and a cancel button.
        uploadRow.axis = .horizontal
        uploadRow.alignment = .center
        uploadRow.spacing = Space.md
        uploadRow.translatesAutoresizingMaskIntoConstraints = false
        uploadRow.isHidden = true

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = Self.ink
        spinner.startAnimating()
        uploadRow.addArrangedSubview(spinner)
        uploadFileLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: UIFont.monospacedSystemFont(ofSize: Self.uploadFileFontSize, weight: .regular))
        uploadFileLabel.adjustsFontForContentSizeCategory = true
        uploadFileLabel.textColor = Self.ink.withAlphaComponent(0.85)
        uploadFileLabel.lineBreakMode = .byTruncatingMiddle
        uploadFileLabel.text = ""
        uploadRow.addArrangedSubview(uploadFileLabel)
        uploadProgress.tintColor = Self.ink
        uploadProgress.trackTintColor = Self.ink.withAlphaComponent(0.25)
        uploadProgress.setProgress(0, animated: false)
        uploadRow.addArrangedSubview(uploadProgress)
        uploadProgress.widthAnchor.constraint(
            equalToConstant: TerminalChrome.uploadProgressWidth
        ).isActive = true
        let cancel = makeKey(image: "xmark", label: "Cancel upload") { [weak self] _ in
            self?.onCancelUpload?()
        }
        uploadRow.addArrangedSubview(cancel)
        uploadFileLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        addSubview(keysArea)
        addSubview(uploadRow)
        NSLayoutConstraint.activate([
            keysArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            keysArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            keysArea.topAnchor.constraint(equalTo: topAnchor, constant: TerminalChrome.keyBarInset),
            keysArea.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -TerminalChrome.keyBarInset),
            uploadRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.md),
            uploadRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.md),
            uploadRow.topAnchor.constraint(equalTo: topAnchor, constant: TerminalChrome.keyBarInset),
            uploadRow.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -TerminalChrome.keyBarInset),
        ])
    }

    /// Swaps the keys row for the upload progress row (or back). Pass nil when idle.
    func setUpload(_ snapshot: TerminalUploadSnapshot?) {
        guard let snapshot else {
            keysArea.isHidden = false
            uploadRow.isHidden = true
            return
        }
        keysArea.isHidden = true
        uploadRow.isHidden = false
        uploadFileLabel.text = snapshot.fileName
        uploadProgress.setProgress(Float(min(1, max(0, snapshot.progress))), animated: true)
    }

    deinit {
        if let resetObserver { NotificationCenter.default.removeObserver(resetObserver) }
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// A key. Every key acts when the finger lifts inside it (so a drag that scrolls the bar never
    /// types); `repeats` keys also act, and keep acting, once held for `repeatDelay`. The press
    /// highlight is `KeyButton`'s, on touch-down either way.
    private func makeKey(
        image: String? = nil, title: String? = nil,
        label: String,
        repeats: Bool = false,
        feedback: Bool = true,
        action: @escaping (UIButton) -> Void
    ) -> UIButton {
        let button = KeyButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.applyStyle()
        if let image {
            button.setImage(
                UIImage(
                    systemName: image,
                    withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .medium)),
                for: .normal)
        } else if let title {
            button.setTitle(title, for: .normal)
            // Scales with Dynamic Type, like the rest of the keyboard.
            button.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                for: UIFont.monospacedSystemFont(ofSize: Self.keyTitleFontSize, weight: .regular))
            button.titleLabel?.adjustsFontForContentSizeCategory = true
        }
        button.accessibilityLabel = label
        // 44 pt tall and drawn at least `minWidth` wide (the glyph decides the rest); the touch
        // area is 44 pt wide either way (`KeyButton.point(inside:with:)`).
        button.heightAnchor.constraint(equalToConstant: TerminalChrome.hit).isActive = true
        button.widthAnchor.constraint(
            greaterThanOrEqualToConstant: TerminalKeyStyle.minWidth
        ).isActive = true
        button.onActivate = action
        if repeats {
            button.addAction(
                UIAction { [weak self, weak button] _ in
                    guard let self, let button else { return }
                    self.beginHold(on: button, feedback: feedback)
                }, for: .touchDown)
            button.addAction(
                UIAction { [weak self, weak button] _ in
                    guard let self, let button else { return }
                    self.endHold(firing: button, feedback: feedback)
                }, for: .touchUpInside)
            button.addAction(
                UIAction { [weak self] _ in self?.endRepeat() },
                for: [.touchUpOutside, .touchCancel, .touchDragExit])
        } else {
            button.addAction(
                UIAction { [weak self, weak button] _ in
                    guard let button else { return }
                    if feedback { self?.tick() }
                    action(button)
                }, for: .touchUpInside)
        }
        return button
    }

    /// The light tap of a key press, with the generator readied for the next one.
    private func tick() {
        Haptics.light()
        Haptics.prepareLight()
    }

    /// An arrow went down: nothing is sent yet (this touch may become a scroll). Held for
    /// `repeatDelay`, it fires once with the tap, then repeats on a steady beat like a hardware key.
    private func beginHold(on button: KeyButton, feedback: Bool) {
        repeatTask?.cancel()
        holdDidFire = false
        repeatTask = Task { [weak self, weak button] in
            try? await Task.sleep(for: TerminalKeyStyle.repeatDelay)
            while !Task.isCancelled {
                guard let self, let button else { return }
                if !self.holdDidFire {
                    self.holdDidFire = true
                    if feedback { self.tick() }
                }
                button.onActivate?(button)
                try? await Task.sleep(for: TerminalKeyStyle.repeatInterval)
            }
        }
    }

    /// The arrow lifted inside the key: a tap sends one press now; a hold already sent its own.
    private func endHold(firing button: KeyButton, feedback: Bool) {
        endRepeat()
        guard !holdDidFire else { return }
        if feedback { tick() }
        button.onActivate?(button)
    }

    private func endRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The keyboard went away with a key held: stop repeating.
        guard window != nil else {
            endRepeat()
            return
        }
        // Ready the haptic, and pick up a Reduce Transparency change made since the last time.
        Haptics.prepareLight()
        refreshKeyColors(in: keysArea)
        refreshKeyColors(in: uploadRow)
    }

    private func refreshKeyColors(in view: UIView) {
        for subview in view.subviews {
            if let key = subview as? KeyButton { key.refreshColors() }
            refreshKeyColors(in: subview)
        }
    }

    private func press(_ text: String) {
        onInput(text)
    }

    private func toggleControl(_ button: UIButton) {
        guard let terminalView else { return }
        // A latched modifier is a mode, so it gets the selection tick instead of a key tap.
        Haptics.selection()
        terminalView.controlModifier.toggle()
        showControl(button, latched: terminalView.controlModifier)
    }

    /// The latched state is a tint, a selected trait and value for VoiceOver, and the key's
    /// highlight (`KeyButton` draws it for a selected key), so it never rides on colour alone.
    private func showControl(_ button: UIButton, latched: Bool) {
        // `KeyButton` draws the tint, fill and edge for a selected key.
        button.isSelected = latched
        button.accessibilityValue =
            latched ? String(localized: "On", bundle: #bundle) : String(localized: "Off", bundle: #bundle)
    }

    private func toggleKeyboard() {
        guard let terminalView else { return }
        if terminalView.isFirstResponder {
            _ = terminalView.resignFirstResponder()
        } else {
            _ = terminalView.becomeFirstResponder()
        }
    }
}
#endif
