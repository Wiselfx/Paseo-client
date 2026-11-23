#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The full-screen chrome: the terminal switcher, New and Exit as glass controls in one
/// container. In the top safe-area band (`spansBand`) it covers no terminal cell, with the
/// switcher at the leading edge and the actions at the trailing edge, clear of the Dynamic
/// Island. Anywhere else it floats top-trailing over the stage and dims to
/// `TerminalChrome.idleOpacity` after `idleDelay`; a dimmed dock still takes its first tap.
struct TerminalFullScreenDock: View {
    let terminals: [TerminalInfo]
    let selectedId: String?
    let dotStates: [String: StatusDot.State]
    let isCreating: Bool
    let spansBand: Bool
    /// Changes when something else wants the user's eyes (an error, a process exit): the dock
    /// wakes up.
    let attention: Int
    let onSelect: (String) -> Void
    let onCreate: () -> Void
    let onExit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isIdle = false
    /// Bumped on every dock action; restarts the idle timer.
    @State private var wake = 0

    private var current: TerminalInfo? { terminals.first { $0.id == selectedId } }

    var body: some View {
        GlassEffectContainer(spacing: TerminalChrome.gap) {
            HStack(spacing: TerminalChrome.gap) {
                if terminals.count > 1, let current {
                    TerminalSwitcherMenu(
                        terminals: terminals, current: current,
                        dotState: dotStates[current.id] ?? .idle,
                        onSelect: select)
                }
                if spansBand { Spacer(minLength: 0) }
                TerminalNewButton(isCreating: isCreating, action: create)
                TerminalFullScreenButton(isFullScreen: true, action: onExit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .opacity(isIdle ? TerminalChrome.idleOpacity : 1)
        // Opacity is the one motion Reduce Motion allows.
        .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: isIdle)
        .onChange(of: selectedId) { wake += 1 }
        .onChange(of: attention) { wake += 1 }
        .onChange(of: spansBand) { wake += 1 }
        .task(id: wake) { await restIfIdle() }
    }

    private func select(_ id: String) {
        wake += 1
        onSelect(id)
    }

    private func create() {
        wake += 1
        onCreate()
    }

    /// Wakes the dock, then lets it rest after the idle delay. Restarting (a new `wake`) cancels
    /// the sleep.
    private func restIfIdle() async {
        isIdle = false
        guard !spansBand else { return }
        try? await Task.sleep(for: TerminalChrome.idleDelay)
        guard !Task.isCancelled else { return }
        isIdle = true
    }
}
#endif
