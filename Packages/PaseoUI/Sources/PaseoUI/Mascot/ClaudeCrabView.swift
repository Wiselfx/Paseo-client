#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

/// M5a: the composer crab (the DSH crab, "Clawd").
///
/// Geometry and state table per `docs/research/08-dsh-live-observation.md` §7. The art is a sprite
/// sheet per animation: one colour sheet and one ink-mask sheet, both drawn on a 52×36 grid of
/// cells at 1 px per cell in the files, shown at 2 pt per cell. Each frame is cropped to the
/// animation's `box` and laid out edge-to-edge, eight per row.
///
/// The crop boxes, frame counts, `still` frames and the 80 ms pace are ported from the DSH
/// source (`packages/client/src/features/mascot/sheets.ts`):
///   · `CRAB_FRAME_MS` — every frame lasts 80 ms.            (sheets.ts:75)
///   · `CRAB_SHEETS` — `frames`/`box`/`still` per animation. (sheets.ts:85-103)
/// Frames per row is 8 for every crab sheet (sheets.ts:68); verified against the sheets'
/// pixel dimensions. The ink mask is filled with the tertiary label ink, so it tints it here
/// with `ClaudePalette.tertiaryInk` (doc 08 §7.2).
///
/// Placement contract (doc 08 §7.1): a 104 × 72 pt frame whose feet sit on the composer card's
/// top edge, the right edge flush with the card's right edge, above the card. The resting body —
/// and only the resting body — takes touches; a tap pokes the crab.
enum CrabAnimation: String, CaseIterable, Sendable {
    case idle
    case idleLook = "idle-look"
    case idleWave = "idle-wave"
    case idleLaptop = "idle-laptop"
    case thinking
    case typing
    case music
    case conducting
    case building
    case error
    case happy
    case notification
    case compacting
    case sleeping
    case waking
    case pokeLeft = "poke-left"
    case pokeRight = "poke-right"
    case tickle
    case drag

    /// The grid the crab is drawn on; one cell is two points on screen.
    static let gridWidth = 52
    static let gridHeight = 36
    static let cellPoints: CGFloat = 2

    /// Every frame lasts 80 ms — `CRAB_FRAME_MS` (sheets.ts:75).
    static let frameSeconds: TimeInterval = 0.08
    /// Frames per sheet row (sheets.ts:68).
    static let columns = 8
    /// pt per animation-cell on screen; the frame display size is `box × 2`.
    static let scale: CGFloat = 2

    struct Sheet: Sendable {
        let frames: Int
        /// `[x, y, width, height]` in cells, as in `sheets.ts:85-103`.
        let box: (x: Int, y: Int, width: Int, height: Int)
        /// The frame shown under Reduce Motion.
        let still: Int
    }

    /// The `CRAB_SHEETS` table, verbatim (sheets.ts:85-103), line for line:
    var sheet: Sheet {
        switch self {
        case .idle: Sheet(frames: 24, box: (24, 20, 24, 16), still: 0) // sheets.ts:85
        case .idleLook: Sheet(frames: 31, box: (24, 20, 24, 16), still: 0) // sheets.ts:86
        case .idleWave: Sheet(frames: 12, box: (24, 15, 24, 21), still: 0) // sheets.ts:87
        case .idleLaptop: Sheet(frames: 43, box: (14, 13, 34, 23), still: 0) // sheets.ts:88
        case .thinking: Sheet(frames: 48, box: (20, 0, 30, 36), still: 24) // sheets.ts:89
        case .typing: Sheet(frames: 6, box: (15, 22, 28, 14), still: 0) // sheets.ts:90
        case .music: Sheet(frames: 16, box: (19, 9, 31, 27), still: 0) // sheets.ts:91
        case .conducting: Sheet(frames: 24, box: (20, 12, 29, 24), still: 0) // sheets.ts:92
        case .building: Sheet(frames: 6, box: (15, 19, 28, 17), still: 0) // sheets.ts:93
        case .error: Sheet(frames: 24, box: (23, 11, 26, 25), still: 4) // sheets.ts:94
        case .happy: Sheet(frames: 32, box: (18, 6, 34, 30), still: 3) // sheets.ts:95
        case .notification: Sheet(frames: 16, box: (24, 8, 24, 28), still: 0) // sheets.ts:96
        case .compacting: Sheet(frames: 20, box: (21, 20, 30, 16), still: 3) // sheets.ts:97
        case .sleeping: Sheet(frames: 32, box: (18, 1, 31, 35), still: 0) // sheets.ts:98
        case .waking: Sheet(frames: 12, box: (24, 4, 24, 32), still: 11) // sheets.ts:99
        case .pokeLeft: Sheet(frames: 10, box: (24, 20, 27, 16), still: 0) // sheets.ts:100
        case .pokeRight: Sheet(frames: 10, box: (21, 20, 27, 16), still: 0) // sheets.ts:101
        case .tickle: Sheet(frames: 16, box: (23, 18, 26, 18), still: 0) // sheets.ts:102
        case .drag: Sheet(frames: 8, box: (23, 12, 26, 22), still: 0) // sheets.ts:103
        }
    }

    /// The frame's display size in points.
    var displaySize: CGSize {
        CGSize(
            width: CGFloat(sheet.box.width) * Self.scale,
            height: CGFloat(sheet.box.height) * Self.scale)
    }

    /// The window's offset from the frame's top-leading corner, in points.
    var windowOffset: CGPoint {
        CGPoint(x: CGFloat(sheet.box.x) * Self.scale, y: CGFloat(sheet.box.y) * Self.scale)
    }

    /// The size of the hit window that plays the poke, in points — the resting body.
    var hitSize: CGSize { displaySize }

    /// Whether taps wake the crab. Only the resting body takes the pointer.
    var isResting: Bool {
        switch self {
        case .idle, .sleeping, .waking: true
        default: false
        }
    }

    /// One poke: `frames` at 80 ms each.
    var pokeDuration: TimeInterval {
        TimeInterval(sheet.frames) * Self.frameSeconds
    }
}

/// Loads and crops the sheets. Everything is read from the app bundle once and cached; the
/// art never touches the network.
@MainActor private enum CrabSheetLoader {
    private static var sheets: [String: UIImage?] = [:]
    private static var crops: [String: UIImage?] = [:]

    static func image(animation: CrabAnimation, ink: Bool) -> UIImage? {
        let key = ink ? "\(animation.rawValue)-ink" : animation.rawValue
        if let cached = sheets[key] { return cached }
        let url =
            Bundle.module.url(forResource: key, withExtension: "png", subdirectory: "Crab")
            ?? Bundle.module.url(forResource: key, withExtension: "png")
        let image = url.flatMap { UIImage(contentsOfFile: $0.path) }
        sheets[key] = image
        return image
    }

    /// The crop for one frame, or nil when the sheet can't produce it.
    static func frame(animation: CrabAnimation, index: Int, ink: Bool) -> UIImage? {
        let key = "\(animation.rawValue)-\(index)-\(ink ? "ink" : "color")"
        if let cached = crops[key] { return cached }
        guard let sheet = image(animation: animation, ink: ink), let cgImage = sheet.cgImage else {
            crops[key] = nil
            return nil
        }
        let spec = animation.sheet
        let box = spec.box
        let columns = CrabAnimation.columns
        let column = index % columns
        let row = index / columns
        // The sheets store 1 px per cell; a frame is `box` cells, cropped edge-to-edge.
        guard
            let image = cgImage.cropping(
                to: CGRect(
                    x: CGFloat(column * box.width),
                    y: CGFloat(row * box.height),
                    width: CGFloat(box.width),
                    height: CGFloat(box.height)))
        else {
            crops[key] = nil
            return nil
        }
        // Raw pixels stay raw: the view scales with nearest-neighbour interpolation.
        let result = UIImage(cgImage: image, scale: 1, orientation: .up)
        crops[key] = result
        return result
    }
}

/// The crab, playing one animation from the sheets. Reduce Motion shows the animation's `still`
/// frame. Taps land only on the resting body, which the caller wires with `onBodyTap`.
struct ClaudeCrabView: View {
    let animation: CrabAnimation
    /// Non-nil only while taps should poke the mascot (the resting body).
    var onBodyTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                // the timeline only needs to tick that often (finding #11).
                TimelineView(.animation(minimumInterval: CrabAnimation.frameSeconds)) { context in
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
                        .foregroundStyle(ClaudePalette.tertiaryInk)
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

/// The composer placement: the machine's animation, with the poke override and the hit area.
/// Feet on the given rect's top edge, right edge flush with its trailing edge.
struct ComposerCrab: View {
    let state: MascotState

    @State private var poke: CrabAnimation?
    @State private var pokeLeftNext = false

    var body: some View {
        let effective = effectiveAnimation
        let tap: (() -> Void)? = effective.isResting ? { pokeNow() } : nil
        ClaudeCrabView(animation: effective, onBodyTap: tap)
            .onChange(of: poke) { _, newValue in
                // A poke plays once (`frames × 80 ms`), then hands the stage back.
                guard let newValue else { return }
                Task {
                    try? await Task.sleep(for: .seconds(newValue.pokeDuration))
                    if poke == newValue { poke = nil }
                }
            }
    }

    private var effectiveAnimation: CrabAnimation {
        if let poke { return poke }
        return state.crabAnimation
    }

    private func pokeNow() {
        Haptics.selection()
        let next: CrabAnimation = pokeLeftNext ? .pokeLeft : .pokeRight
        pokeLeftNext.toggle()
        poke = next
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
