#if canImport(UIKit)
import SwiftUI
import UIKit

/// The height of the window this card is laid out in, reported once when it joins the window and
/// again only when the window resizes — never per scroll frame.
///
/// This replaces `UIScreen.main.bounds.height`, which is deprecated and wrong under Stage Manager,
/// iPad split view and a sheet: a card is bounded by its own window, not by a global screen. The
/// value feeds the 60 %/70 % media caps; a zero height means "no layout yet" and the caller treats
/// the cap as absent.
struct RichViewportHeight: UIViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    @MainActor
    final class ReaderView: UIView {
        var onChange: ((CGFloat) -> Void)?
        private var reported: CGFloat = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        /// Sub-pixel churn during a live resize is dropped; a real window change is reported once.
        private func report() {
            guard let height = window?.bounds.height, height > 0,
                abs(height - reported) >= 1
            else { return }
            reported = height
            onChange?(height)
        }
    }
}
#endif
