#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The stage. Every recently used terminal stays mounted; only the selected one is visible,
/// hit-testable and reachable by VoiceOver, and the others keep applying output with their
/// streams open.
struct TerminalStage: View {
    let store: TerminalsStore
    let uploader: ConversationUpload
    let mounted: [MountedTerminal]
    let selectedTerminalId: String?
    let outgoingTerminalId: String?
    let isSupported: Bool
    let hasTerminals: Bool
    let onExit: (String?, String) -> Void
    let onOutput: (String) -> Void
    let onOpenLink: (TerminalLinkTarget) -> Void
    let onAttach: () -> Void
    let onCreate: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Everything the stage's appearance depends on, so one `.animation` covers the tab
    /// crossfade and a terminal arriving. (The "process ended" card is not part of the stage: it
    /// floats in `TerminalOverlayLayer`.)
    private struct StageState: Equatable {
        var selected: String?
        var mounted: [String]
    }

    private var stageState: StageState {
        StageState(selected: selectedTerminalId, mounted: mounted.map(\.terminalId))
    }

    var body: some View {
        ZStack {
            if mounted.isEmpty {
                TerminalStagePlaceholder(
                    isSupported: isSupported, hasTerminals: hasTerminals, onCreate: onCreate)
            } else {
                ForEach(mounted) { entry in
                    TerminalStageEntry(
                        store: store,
                        uploader: uploader,
                        terminalId: entry.terminalId,
                        isSelected: entry.terminalId == selectedTerminalId,
                        isOutgoing: entry.terminalId == outgoingTerminalId,
                        onExit: { onExit($0, entry.terminalId) },
                        onOutput: { onOutput(entry.terminalId) },
                        onOpenLink: onOpenLink,
                        onAttach: onAttach)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: stageState)
    }
}
#endif
