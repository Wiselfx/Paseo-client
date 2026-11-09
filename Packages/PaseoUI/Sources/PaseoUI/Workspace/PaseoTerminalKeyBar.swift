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
final class PaseoTerminalKeyBar: UIInputView, UIInputViewAudioFeedback {
    private weak var terminalView: TerminalView?
    private let onInput: (String) -> Void
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var ctrlButton: UIButton?
    private var resetObserver: NSObjectProtocol?

    private static let ink = UIColor(red: 0.949, green: 0.937, blue: 0.914, alpha: 1)

    init(terminalView: TerminalView, onInput: @escaping (String) -> Void) {
        self.terminalView = terminalView
        self.onInput = onInput
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.flexibleWidth]
        backgroundColor = UIColor(red: 20 / 255, green: 20 / 255, blue: 19 / 255, alpha: 1)

        let keys = UIStackView()
        keys.axis = .horizontal
        keys.distribution = .fillEqually
        keys.alignment = .center
        keys.spacing = 2
        keys.translatesAutoresizingMaskIntoConstraints = false

        keys.addArrangedSubview(makeKey(image: "escape", label: "Escape") { [weak self] _ in
            self?.press("\u{1b}")
        })
        keys.addArrangedSubview(makeKey(image: "tab", label: "Tab") { [weak self] _ in
            self?.press("\t")
        })
        let ctrl = makeKey(image: "control", label: "Control (sticky, one-shot)") { [weak self] button in
            self?.toggleControl(button)
        }
        ctrlButton = ctrl
        keys.addArrangedSubview(ctrl)
        keys.addArrangedSubview(makeKey(image: "arrow.up", label: "Up arrow") { [weak self] _ in
            self?.terminalView?.sendKeyUp()
        })
        keys.addArrangedSubview(makeKey(image: "arrow.down", label: "Down arrow") { [weak self] _ in
            self?.terminalView?.sendKeyDown()
        })
        keys.addArrangedSubview(makeKey(image: "arrow.left", label: "Left arrow") { [weak self] _ in
            self?.terminalView?.sendKeyLeft()
        })
        keys.addArrangedSubview(makeKey(image: "arrow.right", label: "Right arrow") { [weak self] _ in
            self?.terminalView?.sendKeyRight()
        })
        keys.addArrangedSubview(makeKey(title: "|", label: "Pipe") { [weak self] _ in self?.press("|") })
        keys.addArrangedSubview(makeKey(title: "~", label: "Tilde") { [weak self] _ in self?.press("~") })
        keys.addArrangedSubview(makeKey(title: "/", label: "Slash") { [weak self] _ in self?.press("/") })
        keys.addArrangedSubview(makeKey(title: "-", label: "Minus") { [weak self] _ in self?.press("-") })
        let hide = makeKey(image: "keyboard", label: "Hide keyboard") { [weak self] _ in
            self?.toggleKeyboard()
        }
        keys.addArrangedSubview(hide)

        // SwiftTerm resets controlModifier after the next key; keep the Ctrl button in sync.
        resetObserver = NotificationCenter.default.addObserver(
            forName: .terminalViewControlModifierReset, object: terminalView, queue: .main) { [weak self] _ in
            self?.ctrlButton?.tintColor = Self.ink
        }

        addSubview(keys)
        NSLayoutConstraint.activate([
            keys.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            keys.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            keys.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            keys.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    deinit {
        if let resetObserver { NotificationCenter.default.removeObserver(resetObserver) }
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func makeKey(
        image: String? = nil, title: String? = nil,
        label: String,
        action: @escaping (UIButton) -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        if let image {
            button.setImage(
                UIImage(systemName: image, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)),
                for: .normal)
        } else if let title {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = UIFont(name: ClaudeTypography.anthropicMono, size: 17)
                ?? UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        }
        button.tintColor = Self.ink
        button.setTitleColor(Self.ink, for: .normal)
        button.accessibilityLabel = label
        button.addAction(
            UIAction { _ in
                self.haptic.impactOccurred()
                action(button)
            }, for: .touchUpInside)
        return button
    }

    private func press(_ text: String) {
        onInput(text)
    }

    private func toggleControl(_ button: UIButton) {
        guard let terminalView else { return }
        terminalView.controlModifier.toggle()
        button.tintColor = terminalView.controlModifier ? ClaudePaletteWarm.controlActive : Self.ink
    }

    private func toggleKeyboard() {
        guard let terminalView else { return }
        if terminalView.isFirstResponder {
            terminalView.resignFirstResponder()
        } else {
            terminalView.becomeFirstResponder()
        }
    }
}

/// Warm accent for the sticky Ctrl state, matching ClaudePalette's dark ink on #141413.
private enum ClaudePaletteWarm {
    static let controlActive = UIColor(red: 0.867, green: 0.467, blue: 0.341, alpha: 1) // #DD7757-ish warm
}
#endif
