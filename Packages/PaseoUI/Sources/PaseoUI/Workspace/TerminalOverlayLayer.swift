#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Everything that floats over the stage, in one layer: the full-screen dock, the error banner
/// and the "process ended" card. The layer is an overlay, so none of it can resize the terminal
/// grid (a store error used to take a row off the PTY and force a TUI redraw), and it has no
/// background or content shape, so only the controls themselves take touches.
///
/// The dock sits in the top safe-area band when `dockInBand` (it then occupies no terminal
/// cell, and the layer reaches up into the band by `topInset`); otherwise it floats at the
/// top-trailing corner and the cards sit below it.
struct TerminalOverlayLayer: View {
    let isFullScreen: Bool
    let dockInBand: Bool
    /// The page's top safe-area inset, which is where the stage starts below the window's top.
    let topInset: CGFloat
    let terminals: [TerminalInfo]
    let selectedId: String?
    let dotStates: [String: StatusDot.State]
    let isCreating: Bool
    let error: String?
    let exitMessage: String?
    let onSelect: (String) -> Void
    let onCreate: () -> Void
    let onExitFullScreen: () -> Void
    let onRetry: () -> Void
    let onDismissError: () -> Void
    let onReattach: () -> Void
    let onDismissExit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Reduce Motion: opacity only.
    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    /// Cards start below the dock when the dock floats over the stage.
    private var cardsTopPadding: CGFloat {
        isFullScreen && !dockInBand
            ? TerminalChrome.edge + TerminalChrome.hit + TerminalChrome.gap
            : TerminalChrome.edge
    }

    /// Moves the dock up from the stage's top edge to the middle of the safe-area band.
    private var bandOffset: CGFloat {
        -(topInset + TerminalChrome.hit) / 2
    }

    private var attention: Int {
        (error == nil ? 0 : 1) + (exitMessage == nil ? 0 : 1)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: TerminalChrome.gap) {
                if let error {
                    TerminalErrorBanner(message: error, onRetry: onRetry, onDismiss: onDismissError)
                        .transition(cardTransition)
                }
                if let exitMessage {
                    TerminalExitOverlay(
                        message: exitMessage, onReattach: onReattach, onDismiss: onDismissExit
                    )
                    .transition(cardTransition)
                }
            }
            .padding(.horizontal, TerminalChrome.edge)
            .padding(.top, cardsTopPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if isFullScreen {
                TerminalFullScreenDock(
                    terminals: terminals, selectedId: selectedId, dotStates: dotStates,
                    isCreating: isCreating, spansBand: dockInBand, attention: attention,
                    onSelect: onSelect, onCreate: onCreate, onExit: onExitFullScreen
                )
                .padding(.horizontal, dockInBand ? TerminalChrome.bandEdge : TerminalChrome.edge)
                .padding(.top, dockInBand ? 0 : TerminalChrome.edge)
                .offset(y: dockInBand ? bandOffset : 0)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(
            Motion.disclosure.resolved(reduceMotion: reduceMotion) ?? Motion.fade.animation,
            value: [error != nil, exitMessage != nil, isFullScreen])
    }
}
#endif
