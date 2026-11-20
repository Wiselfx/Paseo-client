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
            // SwiftUI hosts this composer twice (the bottom bar keeps a second instance) and both
            // read the same focus binding. The second instance must never take focus from the one
            // the user is typing in: UIKit would end editing there, the binding would flip to
            // false, and both would resign. That is the "keyboard closes again right after a
            // rewound message was sent" bug. Only take focus when no composer has it.
            if let window = uiView.window, let other = Self.focusedComposer(in: window), other !== uiView {
                return
            }
            if !uiView.isFirstResponder { uiView.becomeFirstResponder() }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    /// The composer text view in `view`'s tree that is first responder, if any.
    private static func focusedComposer(in view: UIView) -> ComposerUITextView? {
        if let field = view as? ComposerUITextView, field.isFirstResponder { return field }
        for subview in view.subviews {
            if let found = focusedComposer(in: subview) { return found }
        }
        return nil
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
            PaseoPerf.mark("composer.focus")
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
#endif
