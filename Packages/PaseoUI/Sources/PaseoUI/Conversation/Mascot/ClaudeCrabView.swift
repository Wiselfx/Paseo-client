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
    @State private var startedAt = Date()

    init(animation: CrabAnimation, onBodyTap: (() -> Void)? = nil) {
        self.animation = animation
        self.onBodyTap = onBodyTap
        self._current = State(initialValue: animation)
    }

    var body: some View {
        Group {
            if CrabSheetLoader.image(animation: current, ink: false) == nil {
                // Hidden until the first sheet frame is ready.
                EmptyView()
            } else if reduceMotion || current == .sleeping {
                // Reduce Motion: the animation's `still` frame, static. The sleeping loop is 32
                // frames forever; the same picture without the display-rate redraw (finding #11).
                frame(at: Date(timeIntervalSinceReferenceDate: 0), index: current.sheet.still)
            } else {
                // The frame clock, not the display clock: the crab changes frame every 80 ms, so
                // the timeline only needs to tick that often (finding #11). It stops entirely
                // while the crab is covered or the app is in the background (R9 §3).
                TimelineView(
                    .animation(minimumInterval: CrabAnimation.frameSeconds, paused: paused)
                ) { context in
                    frame(at: context.date)
                }
            }
        }
        .frame(width: CGFloat(CrabAnimation.gridWidth) * CrabAnimation.cellPoints,
               height: CGFloat(CrabAnimation.gridHeight) * CrabAnimation.cellPoints,
               alignment: .topLeading)
        .onChange(of: animation) { _, newValue in
            current = newValue
            startedAt = Date()
        }
    }

    private var paused: Bool {
        reduceMotion || isSurfaceObscured || scenePhase != .active
    }

    private func frame(at date: Date, index forced: Int? = nil) -> some View {
        let spec = current.sheet
        let elapsed = date.timeIntervalSince(startedAt)
        let index = forced ?? max(0, Int(elapsed / CrabAnimation.frameSeconds)) % spec.frames
        let frameSize = current.displaySize
        let offset = current.windowOffset
        return ZStack(alignment: .topLeading) {
            ZStack {
                if let body = CrabSheetLoader.frame(animation: current, index: index, ink: false) {
                    Image(uiImage: body)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: frameSize.width, height: frameSize.height)
                }
                if let mask = CrabSheetLoader.frame(animation: current, index: index, ink: true) {
                    Image(uiImage: mask)
                        .resizable()
                        .interpolation(.none)
                        .renderingMode(.template)
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(width: frameSize.width, height: frameSize.height)
                }
            }
            .offset(x: offset.x, y: offset.y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            if let onBodyTap, current.isResting {
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .frame(width: current.hitSize.width, height: current.hitSize.height)
                    .offset(x: offset.x, y: offset.y)
                    .onTapGesture { onBodyTap() }
                    .accessibilityLabel("Poke the crab")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
