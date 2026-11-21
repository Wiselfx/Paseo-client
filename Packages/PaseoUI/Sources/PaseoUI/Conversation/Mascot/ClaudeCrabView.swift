#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

/// The crab, playing one animation from the sheets. Reduce Motion shows the animation's `still`
/// frame. Taps land only on the resting body, which the caller wires with `onBodyTap`.
struct ClaudeCrabView: View {
    let animation: CrabAnimation
    /// Non-nil only while taps should poke the mascot (the resting body).
    var onBodyTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSurfaceObscured) private var isSurfaceObscured
    @Environment(\.scenePhase) private var scenePhase
    /// The animation playing right now; restarts the frame clock when it changes.
    @State private var current: CrabAnimation
    @State private var startedAt = Date.now

    init(animation: CrabAnimation, onBodyTap: (() -> Void)? = nil) {
        self.animation = animation
        self.onBodyTap = onBodyTap
        self._current = State(initialValue: animation)
    }

    var body: some View {
        let sheetReady = CrabSheetLoader.image(animation: current, ink: false) != nil
        Group {
            if !sheetReady {
                // Hidden until the first sheet frame is ready.
                EmptyView()
            } else if reduceMotion || current == .sleeping {
                // Reduce Motion: the animation's `still` frame, static. The sleeping loop is 32
                // frames forever; the same picture without the display-rate redraw (finding #11).
                CrabFrame(animation: current, index: current.sheet.still)
            } else {
                // The frame clock, not the display clock: the crab changes frame every 80 ms, so
                // the timeline only needs to tick that often (finding #11). It stops entirely
                // while the crab is covered or the app is in the background (R9 §3).
                TimelineView(
                    .animation(minimumInterval: CrabAnimation.frameSeconds, paused: paused)
                ) { context in
                    CrabFrame(animation: current, index: frameIndex(at: context.date))
                }
            }
        }
        .frame(width: CGFloat(CrabAnimation.gridWidth) * CrabAnimation.cellPoints,
               height: CGFloat(CrabAnimation.gridHeight) * CrabAnimation.cellPoints,
               alignment: .topLeading)
        // The hit target depends on the animation, not the frame, so it sits outside the timeline
        // and is not rebuilt every tick.
        .overlay(alignment: .topLeading) {
            if sheetReady, let onBodyTap, current.isResting {
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .frame(width: current.hitSize.width, height: current.hitSize.height)
                    .offset(x: current.windowOffset.x, y: current.windowOffset.y)
                    .onTapGesture { onBodyTap() }
                    .accessibilityLabel("Poke the crab")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .onChange(of: animation) { _, newValue in
            current = newValue
            startedAt = Date.now
        }
    }

    private var paused: Bool {
        reduceMotion || isSurfaceObscured || scenePhase != .active
    }

    private func frameIndex(at date: Date) -> Int {
        max(0, Int(date.timeIntervalSince(startedAt) / CrabAnimation.frameSeconds)) % current.sheet.frames
    }
}
extension MascotState {
    /// The crab animation that plays this state. Every `MascotState` has a sheet; the
    /// `MascotStateMachine` decides what plays, so a completed turn never shows `error`.
    var crabAnimation: CrabAnimation {
        switch self {
        case .idle: .idle
        case .sleeping: .sleeping
        case .waking: .waking
        case .thinking: .thinking
        case .typing: .typing
        case .music: .music
        case .building: .building
        case .conducting: .conducting
        case .notification: .notification
        case .compacting: .compacting
        case .happy: .happy
        case .error: .error
        }
    }
}
#endif
