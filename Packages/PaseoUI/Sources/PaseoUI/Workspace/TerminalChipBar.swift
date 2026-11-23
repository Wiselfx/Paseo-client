#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The rail along the top of the terminal page: one chip per terminal, scrolling beside a
/// pinned trailing cluster (New, Full Screen). 44 pt tall. The selected chip's glass capsule
/// slides between chips; each chip's status dot comes in as a value, so the bar does not depend
/// on the page's `lastViewed` state.
struct TerminalChipBar: View {
    let terminals: [TerminalInfo]
    let selectedId: String?
    let dotStates: [String: StatusDot.State]
    let isCreating: Bool
    let onSelect: (String) -> Void
    let onRename: (TerminalInfo) -> Void
    let onClose: (TerminalInfo) -> Void
    let onCreate: () -> Void
    let onEnterFullScreen: () -> Void

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: TerminalChrome.gap) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: TerminalChrome.gap) {
                        HStack(spacing: TerminalChrome.gap) {
                            ForEach(terminals) { terminal in
                                TerminalChip(
                                    terminal: terminal,
                                    isSelected: terminal.id == selectedId,
                                    dotState: dotStates[terminal.id] ?? .idle,
                                    namespace: selectionNamespace,
                                    onSelect: { onSelect(terminal.id) },
                                    onRename: { onRename(terminal) },
                                    onClose: { onClose(terminal) })
                            }
                        }
                    }
                    // The glass capsule moves with the selection; Reduce Motion makes it a cut.
                    // Scoped to the chips, so the pinned cluster is never part of the transaction.
                    .animation(Motion.disclosure.resolved(reduceMotion: reduceMotion), value: selectedId)
                    .padding(.horizontal, Space.lg)
                }
                .scrollIndicators(.hidden)
                // A new terminal sorts first and a switch from the dock or a script can pick any
                // chip, so the selected one is always brought into view.
                .onChange(of: selectedId) { _, id in
                    guard let id else { return }
                    withAnimation(Motion.glide.resolved(reduceMotion: reduceMotion)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            GlassEffectContainer(spacing: TerminalChrome.gap) {
                HStack(spacing: TerminalChrome.gap) {
                    TerminalNewButton(isCreating: isCreating, action: onCreate)
                    TerminalFullScreenButton(isFullScreen: false, action: onEnterFullScreen)
                }
            }
            // The full-screen dock's floating inset, so Full Screen sits at the same trailing x
            // on the way in and Exit Full Screen on the way out.
            .padding(.trailing, TerminalChrome.edge)
        }
    }
}
#endif
