#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The conversation's top chrome: the 48 pt header and the find bar, both in the screen's top
/// safe-area bar. Only this struct reads `controller.headerHidden`, so hiding the header
/// re-evaluates it (and the bar it draws) and nothing in the transcript (R-1, H2 §3).
///
/// **Layout:** the bar keeps its height in both states; only the title pill *renders* translated and
/// faded (N6 B). The side buttons never hide. The transcript's top inset is therefore constant, and
/// hiding the header cannot shift a single row.
struct ChatTopChrome: View {
    let store: ConversationStore
    let controller: ChatController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Never hide chrome from VoiceOver.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        VStack(spacing: 0) {
            header
            if controller.find.isOpen {
                ChatFindBarView(store: store, controller: controller)
            }
        }
    }

    /// Everything that keeps the bar on screen whatever the transcript did: find, a sheet or a
    /// dialog the bar opened, and VoiceOver (H2 §3).
    private var pinned: Bool {
        controller.find.isOpen || controller.sheet != nil || controller.showContextSheet
            || controller.showFullScreenComposer || controller.openFilePath != nil
            || controller.renamingAgent || controller.archiveConfirm
            || controller.pendingRewind != nil || voiceOverEnabled
    }

    private var hidden: Bool { controller.headerHidden && !pinned }

    /// Only the title pill hides (N6 B); the bar's side buttons stay where they are, tappable.
    private var header: some View {
        ChatHeaderBar(store: store, controller: controller, titleHidden: hidden)
            .animation(hideAnimation, value: hidden)
    }

    /// Reduce Motion keeps the fade (opacity is allowed) and drops the slide.
    private var hideAnimation: Animation? {
        reduceMotion
            ? Motion.fade.resolved(reduceMotion: true)
            : Motion.header.resolved(reduceMotion: false)
    }
}
#endif
