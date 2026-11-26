#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Cell content

/// The SwiftUI root of one cell: the item, plus the environment the screen would have given it.
struct TranscriptCellRoot: View {
    let entry: TranscriptEntry
    let env: TranscriptCellEnvironment

    var body: some View {
        // The content sits at the cell's top, so a row whose frame lags a growth grows downward
        // instead of the hosting view re-centring it (the per-line bounce while text streamed).
        TranscriptTopPinnedLayout {
            content
                // A recycled cell starts the new turn with fresh state.
                .id(identity)
                // The content is laid out at the column's width and its own height in every pass. The
                // cell is measured with no height offered and drawn with its frame's height; offering
                // the frame's height would let text inside stacks re-wrap between the two (rows that
                // changed shape as they scrolled), and squeeze or stretch a row whose frame has not
                // caught up with a change yet.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .coordinateSpace(.named(TranscriptRowFrames.space))
        .environment(\.chatActions, env.controller.actions)
        .environment(\.richActions, env.controller.richActions)
        .environment(\.openURL, env.openURL)
        .environment(\.toast, env.toast)
        .environment(\.shellDrawer, env.shellDrawer)
        .environment(\.surfaceFlags, env.surfaceFlags)
        .environment(\.codeSizeStep, env.codeSizeStep)
        .environment(\.artifactZoomNamespace, env.artifactZoom)
        .environment(\.richProseWidth, env.column)
        .environment(\.richViewportHeight, env.viewport)
        .environment(\.claudeProcessCap, min(400, env.viewport * 0.5))
        .environment(\.transcriptRowFrames, env.rowFrames)
        .environment(\.isSurfaceObscured, env.ui.surfaceObscured)
        .environment(\.scenePhase, env.ui.scenePhase)
        .foregroundStyle(Palette.ink)
        .tint(Palette.ink)
        // Vertical only: the side insets already narrow the column. A cell is scrolled content: the bars and the home indicator are the collection view's
        // content inset, never the cell's. A cell under a bar is handed that bar's safe area, and
        // the hosting view laid the turn out below it and measured it that much taller, so a turn
        // slid inside its own cell as it crossed a bar and the gap to the next bubble grew and
        // shrank while history scrolled (measured: TranscriptHarnessTests).
        .ignoresSafeArea(edges: .vertical)
    }

    private var identity: String {
        switch entry {
        case .historyStart: "history"
        case .turn(let row): row.turn.id
        case .permissions: "permissions"
        case .resolvedPermissions: "resolved"
        case .backgroundWork: "background"
        }
    }

    @ViewBuilder private var content: some View {
        switch entry {
        case .historyStart:
            TranscriptHistorySlot(
                store: env.store, history: env.history,
                onRetry: { [weak engine = env.engine] in engine?.retryOlderHistory() })
        case .turn(let row):
            row.equatable()
        case .permissions:
            TranscriptPermissionCards(store: env.store)
        case .resolvedPermissions:
            ResolvedPermissionLines(store: env.store)
        case .backgroundWork:
            TranscriptBackgroundWork(store: env.store, controller: env.controller)
        }
    }
}
#endif
