#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Reads the drawer's `\.isSurfaceObscured` in its own body (W1): the sidebar used to read it itself, so
/// every drawer motion re-evaluated the whole directory body to learn one `Bool`. This child owns the two
/// things that depend on it: reloading the usage footer when the drawer shows the sidebar (H4 §2: a
/// commit, not a drag frame) and the five-minute poll that runs only while the summary is on screen and
/// the app is in front (Upstream: packages/app/src/usage/queries.ts:36-39, 182-197).
struct SidebarUsageDriver: View {
    let session: HostSession
    let showUsage: Bool
    let load: () async -> Void

    @Environment(\.isSurfaceObscured) private var isSurfaceObscured
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(
                id: "\(showUsage)|\(session.hostUsage.isSupported)|\(isSurfaceObscured)|\(scenePhase)"
            ) { await poll() }
            .onChange(of: isSurfaceObscured) { _, obscured in
                guard !obscured else { return }
                Task { await load() }
            }
    }

    private func poll() async {
        guard showUsage, session.hostUsage.isSupported, !isSurfaceObscured, scenePhase == .active
        else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(HostUsageStore.automaticPollInterval))
            guard !Task.isCancelled else { return }
            _ = await session.hostUsage.load(forceRefresh: false)
        }
    }
}
#endif
