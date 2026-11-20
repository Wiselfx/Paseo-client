#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The connection, as a standing toast: it never takes layout and never asks for a tap. The
/// socket retries on its own; this view also nudges it on foreground, when the network comes
/// back, and on a slow timer after a refusal. It observes the connection in its own body, so
/// the shell body never does.
struct ConnectionStatusToast: View {
    let session: HostSession
    let toast: ToastCenter

    @Environment(\.scenePhase) private var scenePhase

    private enum Phase: Equatable {
        case connected
        case reconnecting
        case refused
    }

    private var phase: Phase {
        switch session.connection {
        case .idle, .connected: .connected
        case .connecting, .reconnecting: .reconnecting
        case .failed: .refused
        }
    }

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .task(id: phase) { await drive(phase) }
            .task { await watchNetwork() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { session.reconnectNow() }
            }
            .onDisappear { toast.setStatus(nil) }
    }

    private func drive(_ phase: Phase) async {
        switch phase {
        case .connected:
            toast.setStatus(nil)
        case .reconnecting:
            // A blip that heals within a second never shows; an already showing status just
            // changes its words.
            if toast.status == nil {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            toast.setStatus(.init(message: "Reconnecting…", systemImage: nil, showsProgress: true))
        case .refused:
            toast.setStatus(
                .init(message: "Can't reach the host · retrying", systemImage: nil, showsProgress: true))
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                session.reconnectNow()
            }
        }
    }

    /// A network that comes back is the best moment to retry, not the next backoff step.
    private func watchNetwork() async {
        let monitor = NetworkPathMonitor()
        monitor.onChange = { _, _, _, offline in
            if !offline { session.reconnectNow() }
        }
        // Lives as long as this view; cancellation ends the sleep and releases the monitor.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        monitor.stop()
    }
}
#endif
