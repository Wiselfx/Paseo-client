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
/// with `Palette.tertiaryInk` (doc 08 §7.2).
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
#endif
