#if canImport(UIKit)
import SwiftUI
import UIKit

/// The composer's field (D2 §2): a `UITextView` under SwiftUI, because a SwiftUI `TextField` can
/// not receive a pasted image. Everything the old field did stays: the text binding, the focus
/// binding both ways, the placeholder, grow-to-cap-then-scroll, ⌘↩ send (the send button owns the
/// shortcut), and the same accessibility identifier.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    /// The composer's focus, plus where the field reports UIKit's begin/end back (E1 §1).
    ///
    /// A plain `Bool`, not `@FocusState`: SwiftUI only writes a `FocusState` through a
    /// focusable SwiftUI view, and a `UIViewRepresentable` is not one. The whole composer used
    /// to share one `@FocusState` with no view bound to it, so UIKit's `true` was dropped, and
    /// the next keystroke's `updateUIView` saw `false` and resigned the field.
    @Binding var isFocused: Bool
    /// The same string the `TextField`'s prompt showed.
    let placeholder: String
    /// The field grows to this many lines, then scrolls inside itself.
    let lineLimit: Int
    /// Whether the card's corner expand control is on screen. **Written by the field**, from its
    /// own laid-out line count (`ComposerUITextView.evaluateTallness`), and only when the answer
    /// flips: no character estimate, no string scan per keystroke (H3 §2).
    @Binding var expandVisible: Bool
    /// True while the card's corner expand control is drawn over the field: the text column then
    /// stops short of it, so nothing typed there runs under the button (H3 §2).
    let reservesCornerControl: Bool
    /// Images pasted into the field, in pasteboard order.
    let onPasteImages: ([Data]) -> Void

    func makeUIView(context: Context) -> ComposerUITextView {
        let view = ComposerUITextView(frame: .zero)
        view.delegate = context.coordinator
        view.text = text
        view.accessibilityIdentifier = "composer.draft"
        view.applyStyle(placeholder: placeholder)
        view.lineLimit = lineLimit
        view.isTall = expandVisible
        view.reservesCornerControl = reservesCornerControl
        view.onPasteImages = onPasteImages
        view.onTallChanged = { tall in context.coordinator.stageTall(tall) }
        return view
    }

    func updateUIView(_ uiView: ComposerUITextView, context: Context) {
        // The coordinator holds the current bindings; a stale `parent` would write into a dead one.
        context.coordinator.parent = self
        uiView.onPasteImages = onPasteImages
        uiView.lineLimit = lineLimit
        uiView.onTallChanged = { tall in context.coordinator.stageTall(tall) }
        uiView.isTall = expandVisible
        uiView.reservesCornerControl = reservesCornerControl
        uiView.applyStyle(placeholder: placeholder)
        // An external write (a mention, a dictation, a restored draft after a failed create)
        // leaves the caret at the end, where the user was typing. Never while the IME is
        // composing: replacing `text` drops a CJK/dictation composition on the floor, and
        // moving `selectedRange` mid-composition breaks the marked range UIKit is drawing.
        if uiView.markedTextRange == nil, uiView.text != text {
            uiView.text = text
            uiView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        // The expand control is decided by the field's own layout, so a text change that does not
        // change the height still has to reach `layoutSubviews` for its line count to be measured.
        // Scheduling is free; the layout itself is the one UIKit was doing anyway.
        uiView.setNeedsLayout()
        // Record what SwiftUI just rendered before the bridge decides: a re-render that
        // carries the same value is a snapshot, not a command (E1 §1.3).
        let coordinator = context.coordinator
        coordinator.renderedFocusChanged = coordinator.lastRenderedFocus != isFocused
        coordinator.lastRenderedFocus = isFocused
        bridgeFocus(uiView, coordinator: coordinator)
        uiView.updatePlaceholder(visible: text.isEmpty)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: ComposerUITextView, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.fittedSize(width: width)
    }

    /// SwiftUI → first responder, **edge-triggered** (E1 §1).
    ///
    /// `updateUIView` runs on every keystroke (the text binding changed), and a level-triggered
    /// bridge would act on whatever `isFocused` held at that moment. This acts only on an edge:
    /// the value must differ from the one last applied, so a text change or a style pass can
    /// never move the responder chain.
    ///
    /// The one exception is what the tick used to do by accident: while UIKit's begin/end is
    /// travelling back through the binding, every render carries the *old* value. A render that
    /// repeats the value seen at the event is that snapshot, so it waits; a render that changed
    /// is a newer command from the app (send, tap-outside) and it wins.
    private func bridgeFocus(_ uiView: ComposerUITextView, coordinator: Coordinator) {
        if coordinator.pendingEcho != nil {
            guard coordinator.renderedFocusChanged else { return }
            coordinator.pendingEcho = nil
        }
        guard isFocused != coordinator.lastAppliedFocus else { return }
        coordinator.lastAppliedFocus = isFocused
        if isFocused {
            if !uiView.isFirstResponder { uiView.becomeFirstResponder() }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView
        /// The focus value UIKit is in: what the bridge last applied, or what the delegate last
        /// reported. Updated immediately on begin/end, so the echo of its own deferred write is
        /// never mistaken for a command (E1 §1.3).
        var lastAppliedFocus = false
        /// The value SwiftUI rendered at the previous `updateUIView`.
        var lastRenderedFocus: Bool
        /// Whether this render changed that value.
        var renderedFocusChanged = false
        /// A delegate write on its way back through the binding. While it is pending, renders
        /// repeat the pre-event value and must not be read as commands.
        var pendingEcho: (stale: Bool, focused: Bool)?

        init(parent: ComposerTextView) {
            self.parent = parent
            // A fresh `UITextView` is never first responder, whatever the state says: starting
            // from `false` is what lets a composer restored with focus take it on the first
            // update instead of believing it already has.
            self.lastAppliedFocus = false
            self.lastRenderedFocus = parent.isFocused
        }

        func textViewDidChange(_ textView: UITextView) {
            if parent.text != textView.text {
                parent.text = textView.text
                (textView as? ComposerUITextView)?.updatePlaceholder(visible: textView.text.isEmpty)
            }
            // A keystroke on a line that keeps its length changes no size, so nothing else would
            // ask for the layout pass that measures the field's line count.
            textView.setNeedsLayout()
        }

        /// The field's laid-out line count crossed the expand band. Deferred one main-actor turn:
        /// `layoutSubviews` runs inside UIKit's layout pass, and writing a SwiftUI binding from
        /// there is "state during view update". The field reports edges only, so a run of
        /// keystrokes inside the band schedules nothing.
        func stageTall(_ tall: Bool) {
            Task { @MainActor [weak self] in
                guard let self, self.parent.expandVisible != tall else { return }
                self.parent.expandVisible = tall
            }
        }

        // The write is deferred one main-actor turn: UIKit calls these from inside
        // `becomeFirstResponder()`/`resignFirstResponder()`, which `updateUIView` may call in the
        // middle of a SwiftUI update, and writing a binding there is "state during view update".
        // `lastAppliedFocus` is recorded now, so nothing can fight what UIKit just did.
        func textViewDidBeginEditing(_ textView: UITextView) {
            syncFocus(from: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            syncFocus(from: textView)
        }

        /// UIKit began/ended editing. `lastAppliedFocus` records it now; the binding follows one
        /// main-actor turn later, with the **responder state when the write lands**, so a
        /// dismissal that happened in between (send, a sheet, tap-outside) is not undone by a
        /// stale echo. If the app already wrote a different value meanwhile, the echo stands
        /// down and that write wins.
        private func syncFocus(from textView: UITextView) {
            let focused = textView.isFirstResponder
            let stale = parent.isFocused
            guard stale != focused || lastAppliedFocus != focused else { return }
            lastAppliedFocus = focused
            pendingEcho = (stale: stale, focused: focused)
            Task { @MainActor [weak self, weak textView] in
                guard let self, let echo = self.pendingEcho else { return }
                self.pendingEcho = nil
                // Someone wrote the binding after the event: a newer command, not our snapshot.
                guard self.parent.isFocused == echo.stale else { return }
                let nowFocused = textView?.isFirstResponder ?? echo.focused
                if self.parent.isFocused != nowFocused {
                    self.parent.isFocused = nowFocused
                }
                self.lastAppliedFocus = nowFocused
            }
        }
    }
}

/// The field itself. Grows with its content up to `lineLimit` lines, then scrolls; takes images
/// from the pasteboard, one `itemProvider` at a time.
final class ComposerUITextView: UITextView {
    /// Images pasted, in pasteboard order.
    var onPasteImages: (([Data]) -> Void)?
    var lineLimit = 9
    /// The last tallness SwiftUI rendered — the previous value of the hysteresis band. Written by
    /// `updateUIView` (input) and locally when a flip is reported, so a burst of layout passes
    /// before SwiftUI's next render reports each edge once.
    var isTall = false
    /// The field's own layout crossed the band (H3 §2). Called from the layout pass, so the write
    /// that follows is deferred one turn by the bridge.
    var onTallChanged: ((Bool) -> Void)?
    /// While true, the card's corner expand control is drawn over the field, so the text column
    /// stops short of it (H3 §2).
    var reservesCornerControl = false {
        didSet {
            guard reservesCornerControl != oldValue else { return }
            applyTrailingInset()
            setNeedsLayout()
        }
    }

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
        textContainerInset = UIEdgeInsets(
            top: ComposerMetrics.textInsetTop, left: ComposerMetrics.textInsetLeading,
            bottom: ComposerMetrics.textInsetBottom, right: ComposerMetrics.textInsetLeading)
        textContainer.lineFragmentPadding = 0
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
        // Sizing laid the text out: this is the cheapest moment to read the line count it produced.
        evaluateTallness(contentHeight: content.height)
        return CGSize(width: width, height: ceil(height))
    }

    /// Whether the draft is tall enough for the corner expand control, decided from **this view's
    /// own layout** — the layout manager's used height over the font's line height — instead of
    /// from a character estimate (H3 §2). The real wrap at the real width in the real font, so
    /// Dynamic Type, proportional glyphs, a Mac window and the full-screen composer all agree.
    ///
    /// Sticky between `ComposerMetrics.expandShowLines` and `expandHideLines`, and the report is
    /// an **edge**: the caller's body is invalidated when the answer flips, never per keystroke.
    ///
    /// The band is what keeps the control's own reserve from feeding back into this: the reserve
    /// narrows the text column, and a narrower column can only add lines, so appearing cannot drop
    /// the count into the hide threshold; losing the reserve widens it back, and a wider column can
    /// only remove lines, so disappearing cannot climb into the show threshold. The field is stuck
    /// at `lineLimit` and scrolls, but `usedRect` is the whole document, so the count is the
    /// draft's, not the visible part's.
    private func evaluateTallness(contentHeight: CGFloat) {
        let lines = visualLineCount(contentHeight: contentHeight)
        let tall =
            isTall
            ? lines > ComposerMetrics.expandHideLines : lines >= ComposerMetrics.expandShowLines
        guard tall != isTall else { return }
        isTall = tall
        onTallChanged?(tall)
    }

    /// The draft's visual line count as UIKit laid it out: the laid-out text height (the content
    /// height minus the container insets) divided by the font's line height, rounded. Measured from
    /// the height UIKit already computed, never through `layoutManager`: touching `layoutManager`
    /// on a TextKit 2 text view permanently drops it into TextKit 1 compatibility mode (slower
    /// layout, IME and Writing Tools regressions). Empty text still counts one.
    private func visualLineCount(contentHeight: CGFloat) -> Int {
        guard let lineHeight = font?.lineHeight, lineHeight > 0 else { return 1 }
        let used = contentHeight - textContainerInset.top - textContainerInset.bottom
        return max(1, Int((used / lineHeight).rounded()))
    }

    /// While the card's corner expand control is drawn, the field's trailing inset grows to the
    /// control's own 44 pt width, so no glyph — and no placeholder — ever runs under the button or
    /// under its touch target (H3 §2).
    ///
    /// The whole field, deliberately: a field this tall is scrolling inside its cap
    /// (`fittedSize`), so any line can be the one at the top of the visible area. A text-container
    /// exclusion region would narrow only the document's first line and leave every line the user
    /// scrolls to underneath the button.
    ///
    /// It is written only when the control appears or disappears. `ComposerUITextView` makes that
    /// decision sticky between two laid-out line counts (`ComposerMetrics.expandShowLines` /
    /// `expandHideLines`), so a word wrapping at the threshold cannot re-wrap the draft on
    /// consecutive keystrokes.
    private func applyTrailingInset() {
        let right = reservesCornerControl
            ? ComposerMetrics.hitSize : ComposerMetrics.textInsetLeading
        guard textContainerInset.right != right else { return }
        textContainerInset.right = right
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = textContainerInset
        let width = max(0, bounds.width - inset.left - inset.right)
        let height = placeholderLabel.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
        placeholderLabel.frame = CGRect(x: inset.left, y: inset.top, width: width, height: height)
        // The text is laid out here: `contentSize` is the whole document at the current width.
        evaluateTallness(contentHeight: contentSize.height)
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
