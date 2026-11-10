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
/// One-line snapshot of an in-flight T14 (`file.upload`) transfer, for the key bar's progress
/// row. `progress` is 0…1 bytes-sent; the daemon answers only after all bytes arrive.
struct TerminalUploadSnapshot: Equatable {
    let fileName: String
    let progress: Double
}

final class PaseoTerminalKeyBar: UIInputView, UIInputViewAudioFeedback {
    private weak var terminalView: TerminalView?
    private let onInput: (String) -> Void
    private var ctrlButton: UIButton?
    /// Written once in init, read once in deinit (which is nonisolated).
    nonisolated(unsafe) private var resetObserver: NSObjectProtocol?
    private let keysRow = UIStackView()
    private let uploadRow = UIStackView()
    private let uploadFileLabel = UILabel()
    private let uploadProgress = UIProgressView(progressViewStyle: .default)

    private static let ink = UIColor(Palette.ink)

    /// Set by the coordinator; invoked when the paperclip is tapped.
    var onAttach: (() -> Void)?
    /// Set by the coordinator; invoked when the upload row's cancel button is tapped.
    var onCancelUpload: (() -> Void)?

    init(terminalView: TerminalView, onInput: @escaping (String) -> Void) {
        self.terminalView = terminalView
        self.onInput = onInput
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.flexibleWidth]
        backgroundColor = UIColor(Palette.background)

        let keys = keysRow
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
        keys.addArrangedSubview(makeKey(image: "paperclip", label: "Attach a file") { [weak self] _ in
            self?.onAttach?()
        })
        let hide = makeKey(image: "keyboard", label: "Hide keyboard") { [weak self] _ in
            self?.toggleKeyboard()
        }
        keys.addArrangedSubview(hide)

        // SwiftTerm resets controlModifier after the next key; keep the Ctrl button in sync.
        resetObserver = NotificationCenter.default.addObserver(
            forName: .terminalViewControlModifierReset, object: terminalView, queue: .main) { [weak self] _ in
            // Delivered on the main queue, so the main actor is already current.
            MainActor.assumeIsolated {
                self?.ctrlButton?.tintColor = Self.ink
            }
        }

        // The upload row replaces the keys while a T14 file transfer is in flight: spinner,
        // file name, byte progress and a cancel button.
        uploadRow.axis = .horizontal
        uploadRow.alignment = .center
        uploadRow.spacing = 10
        uploadRow.translatesAutoresizingMaskIntoConstraints = false
        uploadRow.isHidden = true

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = Self.ink
        spinner.startAnimating()
        uploadRow.addArrangedSubview(spinner)
        uploadFileLabel.font = UIFont(name: ClaudeTypography.anthropicMono, size: 12)
            ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        uploadFileLabel.textColor = Self.ink.withAlphaComponent(0.85)
        uploadFileLabel.lineBreakMode = .byTruncatingMiddle
        uploadFileLabel.text = ""
        uploadRow.addArrangedSubview(uploadFileLabel)
        uploadProgress.tintColor = Self.ink
        uploadProgress.trackTintColor = Self.ink.withAlphaComponent(0.25)
        uploadProgress.setProgress(0, animated: false)
        uploadRow.addArrangedSubview(uploadProgress)
        uploadProgress.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let cancel = makeKey(image: "xmark", label: "Cancel upload") { [weak self] _ in
            self?.onCancelUpload?()
        }
        uploadRow.addArrangedSubview(cancel)
        uploadFileLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        addSubview(keysRow)
        addSubview(uploadRow)
        NSLayoutConstraint.activate([
            keysRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            keysRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            keysRow.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            keysRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            uploadRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            uploadRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            uploadRow.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            uploadRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    /// Swaps the keys row for the upload progress row (or back). Pass nil when idle.
    func setUpload(_ snapshot: TerminalUploadSnapshot?) {
        guard let snapshot else {
            keysRow.isHidden = false
            uploadRow.isHidden = true
            return
        }
        keysRow.isHidden = true
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
                Haptics.light()
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
        button.tintColor = terminalView.controlModifier ? UIColor(Palette.orange) : Self.ink
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
