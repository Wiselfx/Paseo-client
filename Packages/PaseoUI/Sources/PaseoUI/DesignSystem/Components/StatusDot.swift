#if canImport(UIKit)
import SwiftUI

/// The surface is not visible (a sheet covers it, the app is backgrounded): running pulses stop.
private struct SurfaceObscuredKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSurfaceObscured: Bool {
        get { self[SurfaceObscuredKey.self] }
        set { self[SurfaceObscuredKey.self] = newValue }
    }
}

/// The one status dot: 8 pt, one meaning per color, one pulse.
struct StatusDot: View {
    enum State {
        case running
        case attention
        case failed
        case idle
        case unread
    }

    private let state: State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSurfaceObscured) private var isSurfaceObscured
    @State private var pulsing = false

    init(_ state: State) {
        self.state = state
    }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 8, height: 8)
            .overlay {
                if case .idle = state {
                    Circle().strokeBorder(Palette.captionInk, lineWidth: 1)
                }
            }
            .opacity(pulses ? (pulsing ? 1 : 0.35) : 1)
            .animation(animation, value: pulsing)
            .onAppear {
                guard pulses else { return }
                pulsing = true
            }
            .accessibilityHidden(true)
    }

    /// The continuous loop the pulse needs: not under Reduce Motion, not while the surface is
    /// covered.
    private var pulses: Bool {
        guard case .running = state else { return false }
        return !isSurfaceObscured && !reduceMotion
    }

    private var animation: Animation? {
        pulses ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : nil
    }

    private var fill: Color {
        switch state {
        case .running: Palette.ink
        case .attention: Palette.orange
        case .failed: Palette.failureInk
        case .idle: .clear
        case .unread: Palette.unread
        }
    }
}

#Preview("Light") {
    HStack(spacing: Space.md) {
        StatusDot(.running)
        StatusDot(.attention)
        StatusDot(.failed)
        StatusDot(.idle)
        StatusDot(.unread)
        StatusDot(.running).environment(\.isSurfaceObscured, true)
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    HStack(spacing: Space.md) {
        StatusDot(.running)
        StatusDot(.attention)
        StatusDot(.failed)
        StatusDot(.idle)
        StatusDot(.unread)
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
