#if canImport(UIKit)
import SwiftUI
import UIKit

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
        // The placeholder is a plain subview, and a text view is itself the accessibility element,
        // so VoiceOver never visits it: the field's name is the placeholder's text.
        if accessibilityLabel != text { accessibilityLabel = text }
    }

    func updatePlaceholder(visible: Bool) {
        placeholderLabel.isHidden = !visible
    }

    /// The height the field wants at `width`: its content, capped at `lineLimit` lines. Above the
    /// cap it scrolls inside itself instead of pushing the controls row under the keyboard.
    /// Everything `sizeThatFits` reads for this field, so a hit is exactly an uncached call (W1).
    private struct FitKey: Equatable {
        let text: String
        let width: CGFloat
        let fontName: String
        let fontSize: CGFloat
        let insets: UIEdgeInsets
        let category: UIContentSizeCategory
        let exclusions: Int
        let padding: CGFloat
        let lines: Int
    }

    private var fitMemo: (key: FitKey, size: CGSize)?

    /// The text's laid-out size at `width`. SwiftUI asks for it several times per keystroke (ideal,
    /// proposed, after the binding write) and each call is a full TextKit layout of the draft plus a
    /// language-identification pass inside UIKit; the answer only changes when the text, the width,
    /// the font or the insets do.
    private func contentSize(width: CGFloat) -> CGSize {
        let key = FitKey(
            text: text ?? "", width: width, fontName: font?.fontName ?? "",
            fontSize: font?.pointSize ?? 0, insets: textContainerInset,
            category: traitCollection.preferredContentSizeCategory,
            exclusions: textContainer.exclusionPaths.count,
            padding: textContainer.lineFragmentPadding,
            lines: textContainer.maximumNumberOfLines)
        if let memo = fitMemo, memo.key == key {
            PaseoPerf.count("fit.hit")
            return memo.size
        }
        PaseoPerf.count("fit.miss")
        let size = PaseoPerf.measure("fit.layout") {
            sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        }
        fitMemo = (key, size)
        return size
    }

    func fittedSize(width: CGFloat) -> CGSize {
        let lineHeight = ceil(font?.lineHeight ?? Typography.chatBodySize * 1.4)
        let cap = lineHeight * CGFloat(max(lineLimit, 1))
            + textContainerInset.top + textContainerInset.bottom
        let content = contentSize(width: width)
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
        PaseoPerf.count("composer.canPerform")
        if action == #selector(paste(_:)), PasteboardImageState.shared.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        guard PasteboardImageState.shared.hasImages else {
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
