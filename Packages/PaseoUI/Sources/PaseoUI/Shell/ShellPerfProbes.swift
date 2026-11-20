#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// W1: which of the shell's inputs move, and how often (`-paseo-perf` only; never mounted
/// otherwise). Reads live here so the shell's own body gains no dependency.
struct ShellPerfProbes: View {
    let session: HostSession
    let conversation: ConversationStore?

    var body: some View {
        let _ = PaseoPerf.body("ShellProbes")
        Group {
            PerfProbe("conv.agent", conversation?.agent)
            PerfProbe("dir.loaded", session.workspaceDirectory.hasLoaded)
            PerfProbe("dir.error", session.workspaceDirectory.error)
            PerfProbe("connection", session.connection)
            PerfProbe("agents.ids", session.agents.map(\.id))
            PerfProbe("agents.count", session.agents.count)
        }
    }
}
#endif
