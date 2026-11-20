#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// "Back to the end": offered once you are more than a screen from the end of the content
/// (D1 §3). It fades and scales in from 0.9 through `Motion.fade`, and tapping it turns follow
/// back on at once. Hidden, it stays in place, so nothing else can move when it comes and goes.
///
/// It is hosted by the **transcript**, as an `.overlay(alignment: .bottom)` (J3 §2). It used to
/// hang above the composer bar through `.overlay(alignment: .top)` on `bottomChrome`, pushed out
/// with `.alignmentGuide(.top)`; the bar is itself hosted by `.safeAreaBar(edge: .bottom)`, whose
/// host does not hit-test outside the bar's own frame, so every touch on the circle landed on the
/// transcript underneath (which only drops the keyboard) and the button looked dead.
///
/// On the transcript, the overlay respects the safe area the bottom bar and the keyboard
/// contribute, so the button sits `Space.sm` above the bar — and above the subagent pill — moves
/// with the keyboard and with the composer's growth, and needs no inset arithmetic. The old
/// placement padded the scroll view's overlay by `geometry.contentInsets.bottom`, which the bottom
/// `safeAreaBar` already contributes to the scroll view's frame, so the composer (and the keyboard)
/// was counted twice.
struct TranscriptBackToEndButton: View {
    let controller: ChatController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shows = controller.showsBackToEnd && !controller.find.isOpen
        Button {
            controller.returnToEnd()
        } label: {
            Image(systemName: "arrow.down")
                .font(.glyph(.regular, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .frame(width: 44, height: 44)
                .background(Palette.panel, in: .circle)
                .overlay {
                    Circle().strokeBorder(Palette.cardBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(BackToEndPressStyle())
        .opacity(shows ? 1 : 0)
        .scaleEffect(shows ? 1 : 0.9)
        .allowsHitTesting(shows)
        .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: shows)
        .accessibilityHidden(!shows)
        .accessibilityIdentifier("transcript.backToEnd")
        .accessibilityLabel("Back to the end")
    }
}
#endif
