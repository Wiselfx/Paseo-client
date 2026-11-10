#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The composer's field (D2 §2): a `UITextView` under SwiftUI, because a SwiftUI `TextField` can
/// not receive a pasted image. Everything the old field did stays: the text binding, the focus
/// binding both ways, the placeholder, grow-to-cap-then-scroll, ⌘↩ send (the send button owns the
/// shortcut), and the same accessibility identifier.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    /// The `@FocusState` value. The composer's body reads it to build this view, so a focus
    /// change re-runs `updateUIView` — the only place `becomeFirstResponder` can be called.
    let isFocused: Bool
    /// Where the field reports the keyboard's own begin/end back to SwiftUI.
    let focus: FocusState<Bool>.Binding
    /// The same string the `TextField`'s prompt showed.
    let placeholder: String
    /// The field grows to this many lines, then scrolls inside itself.
    let lineLimit: Int
    /// Images pasted or dropped onto the field, in pasteboard order.
    let onPasteImages: ([Data]) -> Void

    func makeUIView(context: Context) -> ComposerUITextView {
        let view = ComposerUITextView(frame: .zero)
        view.delegate = context.coordinator
        view.text = text
        view.accessibilityIdentifier = "composer.draft"
        view.applyStyle(placeholder: placeholder)
        view.lineLimit = lineLimit
        view.onPasteImages = onPasteImages
        return view
    }

    func updateUIView(_ uiView: ComposerUITextView, context: Context) {
        // The coordinator holds the current bindings; a stale `parent` would write into a dead one.
        context.coordinator.parent = self
        uiView.onPasteImages = onPasteImages
        uiView.lineLimit = lineLimit
        uiView.applyStyle(placeholder: placeholder)
        if uiView.text != text {
            uiView.text = text
            // An external write (a mention, a dictation, a restored draft after a failed create)
            // leaves the caret at the end, where the user was typing.
            uiView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        bridgeFocus(uiView)
        uiView.updatePlaceholder(visible: text.isEmpty)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: ComposerUITextView, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.fittedSize(width: width)
    }

    /// `@FocusState` → first responder. The delegate reports the other direction.
    private func bridgeFocus(_ uiView: ComposerUITextView) {
        if isFocused {
            guard !uiView.isFirstResponder else { return }
            uiView.becomeFirstResponder()
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView

        init(parent: ComposerTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard parent.text != textView.text else { return }
            parent.text = textView.text
            (textView as? ComposerUITextView)?.updatePlaceholder(visible: textView.text.isEmpty)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard !parent.focus.wrappedValue else { return }
            parent.focus.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            guard parent.focus.wrappedValue else { return }
            parent.focus.wrappedValue = false
        }
    }
}

/// The field itself. Grows with its content up to `lineLimit` lines, then scrolls; accepts images
/// from the pasteboard and from a drop, one `itemProvider` at a time.
final class ComposerUITextView: UITextView {
    /// Images pasted or dropped, in pasteboard order.
    var onPasteImages: (([Data]) -> Void)?
    var lineLimit = 9

    private let placeholderLabel = UILabel()
    private var appliedSize: CGFloat = 0

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isScrollEnabled = false
        backgroundColor = .clear
        textColor = UIColor(Palette.ink)
        tintColor = UIColor(Palette.ink)
        adjustsFontForContentSizeCategory = true
        textContainerInset = UIEdgeInsets(top: 7, left: 6, bottom: 1, right: 6)
        textContainer.lineFragmentPadding = 0
        // Images dropped onto the field come through the same paste path as ⌘V (D2 §2).
        pasteConfiguration = UIPasteConfiguration(
            acceptableTypeIdentifiers: [UTType.image.identifier, UTType.plainText.identifier])
        placeholderLabel.textColor = UIColor(Palette.secondaryInk)
        placeholderLabel.numberOfLines = 1
        placeholderLabel.lineBreakMode = .byTruncatingTail
        placeholderLabel.adjustsFontForContentSizeCategory = true
        addSubview(placeholderLabel)
    }

    /// The body face from `Typography`, scaled by the user's Dynamic Type setting.
    func applyStyle(placeholder text: String) {
        let body = Typography.uiFont(.body)
        if appliedSize != body.pointSize {
            appliedSize = body.pointSize
            font = body
            placeholderLabel.font = body
            setNeedsLayout()
        }
        if placeholderLabel.text != text { placeholderLabel.text = text }
    }

    func updatePlaceholder(visible: Bool) {
        placeholderLabel.isHidden = !visible
    }

    /// The height the field wants at `width`: its content, capped at `lineLimit` lines. Above the
    /// cap it scrolls inside itself instead of pushing the controls row under the keyboard.
    func fittedSize(width: CGFloat) -> CGSize {
        let lineHeight = ceil(font?.lineHeight ?? Typography.chatBodySize * 1.4)
        let cap = lineHeight * CGFloat(max(lineLimit, 1))
            + textContainerInset.top + textContainerInset.bottom
        let content = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let height = min(content.height, cap)
        let scrolls = content.height > cap + 0.5
        if isScrollEnabled != scrolls { isScrollEnabled = scrolls }
        return CGSize(width: width, height: ceil(height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = textContainerInset
        let width = max(0, bounds.width - inset.left - inset.right)
        let height = placeholderLabel.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
        placeholderLabel.frame = CGRect(x: inset.left, y: inset.top, width: width, height: height)
    }

    // MARK: Paste

    /// UIKit hides Paste while the pasteboard holds nothing the text view can take; an image is
    /// something this field can take (D2 §2).
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasImages else {
            super.paste(sender)
            return
        }
        // Text and images together: the text goes in the field, the images into the tray.
        if let text = pasteboard.string, !text.isEmpty {
            insertText(text)
        }
        Task { @MainActor [weak self] in
            let images = await PasteImageLoader.loadAll()
            self?.onPasteImages?(images)
        }
    }
}
#endif
