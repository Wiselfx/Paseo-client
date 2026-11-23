#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The stage. Every recently used terminal stays mounted; only the selected one is visible,
/// hit-testable and reachable by VoiceOver, and the others keep applying output with their
/// streams open.
///
/// Equatable on its values, and shown with `.equatable()`: the page re-evaluates for chrome
/// (the dock, a card, the New spinner, a dot, typing a rename), and none of that may reach the
/// emulators, whose `updateUIView` re-runs the coordinator's attach and resize path. The callbacks
/// are not part of `==`; they only reach the page's `@State` and its stable stores, so a skipped
/// stage keeps working ones.
struct TerminalStage: View, Equatable {
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

    /// Compared off the main actor: every compared input is a plain value or a store's identity.
    nonisolated static func == (lhs: TerminalStage, rhs: TerminalStage) -> Bool {
        lhs.store === rhs.store && lhs.uploader === rhs.uploader
            && lhs.mounted == rhs.mounted
            && lhs.selectedTerminalId == rhs.selectedTerminalId
            && lhs.outgoingTerminalId == rhs.outgoingTerminalId
            && lhs.isSupported == rhs.isSupported && lhs.hasTerminals == rhs.hasTerminals
    }

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
