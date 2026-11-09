#if canImport(UIKit)
import SwiftUI

/// The waiting line's loader (`docs/research/08-dsh-live-observation.md` §2): an 18 × 14 box holding
/// three lanes of 4 pt `#D97757` dots. Lane A bounces, lane B walks three harmonic lines through
/// one point, lane C swaps the four corners of a 9.5 × 11.6 rectangle. The lane in play rotates
/// every 10 s and hands over to the next over 480 ms; a motion never follows itself. Dots sit on
/// the floor of the box, which aligns with the label's 24 pt line. The harmonic lane leaps above
/// the box, so the drawing canvas straddles the 14 pt frame (its ink reaches a few points past it,
/// exactly as the web row does) without affecting layout.
struct ClaudeLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The lane in play when the loader mounts — at random, and never repeating itself.
    @State private var startLane = Int.random(in: 0..<3)
    @State private var start = Date()

    private static let laneCount = 3
    /// The canvas is taller than the box: it straddles it, centred, so nothing clips.
    private static let canvasHeight: CGFloat = 40
    /// The box's top edge inside the canvas.
    private let canvasTop: Double = 13
    /// The box's floor inside the canvas (box is 14 pt tall).
    private let canvasFloor: Double = 27

    var body: some View {
        if reduceMotion {
            // Static three-dot glyph: no wave, no rotation, no hand-over.
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(ClaudePalette.orange).frame(width: 4, height: 4)
                }
            }
            .frame(width: 18, height: 14, alignment: .bottom)
            .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: 18, height: 14)
                .overlay {
                    // No interval: the schedule follows the display (120 Hz on ProMotion), so
                    // the dots are as smooth as the rest of the app (P3).
                    TimelineView(.animation) { context in
                        Canvas { canvas, _ in
                            draw(canvas, time: max(0, context.date.timeIntervalSince(start)))
                        }
                        .frame(width: 18, height: Self.canvasHeight)
                    }
                }
                .accessibilityHidden(true)
        }
    }

    // MARK: The 10 s clock and the 480 ms hand-over

    private enum Lane: Int {
        case bounce, line, orbit
    }

    private func draw(_ canvas: GraphicsContext, time: Double) {
        let slot = floor(time / ClaudeMotion.dotRotate)
        let tau = time - slot * ClaudeMotion.dotRotate
        let active = Lane(rawValue: (startLane + Int(slot)) % Self.laneCount) ?? .bounce
        var outgoing: Lane?
        var incomingAlpha: Double = 1
        if tau < ClaudeMotion.dotMorph {
            if slot > 0 {
                outgoing = Lane(rawValue: (startLane + Int(slot) + Self.laneCount - 1) % Self.laneCount)
            }
            incomingAlpha = Easing.easeInOut(tau / ClaudeMotion.dotMorph)
        }
        if let outgoing {
            drawLane(outgoing, into: canvas, time: time, alpha: 1 - incomingAlpha)
        }
        drawLane(active, into: canvas, time: time, alpha: incomingAlpha)
    }

    private func drawLane(_ lane: Lane, into canvas: GraphicsContext, time: Double, alpha: Double) {
        guard alpha > 0.001 else { return }
        switch lane {
        case .bounce: drawBounce(into: canvas, time: time, alpha: alpha)
        case .line: drawLine(into: canvas, time: time, alpha: alpha)
        case .orbit: drawOrbit(into: canvas, time: time, alpha: alpha)
        }
    }

    private func dot(
        _ canvas: GraphicsContext, centreX: Double, bottom: Double, width: Double, height: Double,
        alpha: Double
    ) {
        let rect = CGRect(
            x: centreX - width / 2, y: canvasFloor - bottom - height, width: width, height: height)
        canvas.fill(Path(ellipseIn: rect), with: .color(ClaudePalette.orange.opacity(alpha)))
    }

    // MARK: Lane A — bounce (3 dots, 500 ms, infinite alternate, ease)

    private func drawBounce(into canvas: GraphicsContext, time: Double, alpha: Double) {
        let period = 0.5
        let shifts = [0.5, 0.3, 0.2] // negative delays -500 / -300 / -200 ms: the wave is already running
        for index in 0..<3 {
            let u = (time + shifts[index]) / period
            let cycle = u - floor(u)
            let forward = Int(floor(u)) % 2 == 0
            let p = forward ? cycle : 1 - cycle // keyframe position: 0 at the floor, 1 at the top
            // CSS `ease` for the last segment; straight lines up to 60 % per the keyframes.
            let rise: Double
            if p <= 0.6 {
                rise = 8 * p
            } else {
                rise = 4.8 + 3.2 * CubicBezier.standardEase((p - 0.6) / 0.4)
            }
            let squash = max(0, 1 - p / 0.4) // 1 at the floor, round by 40 % of the hop
            let height = 4 * (1 - 0.75 * squash)
            let width = 4 * (1 + 0.7 * squash)
            dot(canvas, centreX: 2 + 7 * Double(index), bottom: rise, width: width, height: height, alpha: alpha)
        }
    }

    // MARK: Lane B — line (3 dots, 1250 ms, harmonic)

    private func drawLine(into canvas: GraphicsContext, time: Double, alpha: Double) {
        let period = 1.25
        // Delays -1/4, -7/12, -11/12 of the period (doc 08 §2.3; same modulo 1 as the triple printed in §2.5b).
        let phases = [0.75, 5.0 / 12, 1.0 / 12]
        // Each dot walks a line through one common point, 120° apart; offsets are the keyframe
        // translates relative to each dot's resting place (left 0/7/14, bottom 0).
        let starts = [CGPoint(x: 7, y: 0), CGPoint(x: 6.928, y: -4), CGPoint(x: -0.072, y: -12)]
        let ends = [CGPoint(x: 7, y: -16), CGPoint(x: -6.928, y: -12), CGPoint(x: -13.856, y: -4)]
        let rests = [0.0, 7.0, 14.0]
        for index in 0..<3 {
            let t = time / period + phases[index]
            let f = (1 - cos(2 * .pi * t)) / 2 // end to end, harmonic
            let x = rests[index] + starts[index].x + (ends[index].x - starts[index].x) * f
            let yOffset = starts[index].y + (ends[index].y - starts[index].y) * f
            let scale = 1 - 0.45 * pow(sin(2 * .pi * t), 2) // 0.55× crossing the middle
            let size = 4 * scale
            // transform-origin 50% 100%: the dot shrinks about its own bottom edge.
            dot(canvas, centreX: x + 2, bottom: -yOffset, width: size, height: size, alpha: alpha)
        }
    }

    // MARK: Lane C — orbit (4 dots, 2400 ms linear; ports the keyframe tables verbatim)

    /// (percent, x, y) corner offsets in px, from `chat-wait.css` `dsh-claude-wait-dot-orbit-1..4`.
    private static let orbitKeyframes: [[(Double, Double, Double)]] = [
        // orbit-1 (dot 1): top-left ↔ bottom-right, A-run at 0–16.67 % and 50–66.67 %.
        [
            (0, -4.75, -5.8), (0.46, -4.57, -3.54), (0.97, -4.03, -1.36), (1.55, -3.15, 0.64),
            (2.26, -1.97, 2.4), (3.21, -0.53, 3.85), (4.6, 1.11, 4.92), (7.09, 2.9, 5.58),
            (16.67, 4.75, 5.8), (50, 4.75, 5.8), (50.46, 4.57, 3.54), (50.97, 4.03, 1.36),
            (51.55, 3.15, -0.64), (52.26, 1.97, -2.4), (53.21, 0.53, -3.85), (54.6, -1.11, -4.92),
            (57.09, -2.9, -5.58), (66.67, -4.75, -5.8), (100, -4.75, -5.8),
        ],
        // orbit-2 (dot 2): top-right ↔ bottom-left, B-run at 25–41.67 % and 75–91.67 %.
        [
            (0, 4.75, -5.8), (25, 4.75, -5.8), (25.46, 4.57, -3.54), (25.97, 4.03, -1.36),
            (26.55, 3.15, 0.64), (27.26, 1.97, 2.4), (28.21, 0.53, 3.85), (29.6, -1.11, 4.92),
            (32.09, -2.9, 5.58), (41.67, -4.75, 5.8), (75, -4.75, 5.8), (75.46, -4.57, 3.54),
            (75.97, -4.03, 1.36), (76.55, -3.15, -0.64), (77.26, -1.97, -2.4), (78.21, -0.53, -3.85),
            (79.6, 1.11, -4.92), (82.09, 2.9, -5.58), (91.67, 4.75, -5.8), (100, 4.75, -5.8),
        ],
        // orbit-4 (dot 3): bottom-right ↔ top-left, A-run at 0–16.67 % and 50–66.67 %.
        [
            (0, 4.75, 5.8), (0.46, 4.57, 3.54), (0.97, 4.03, 1.36), (1.55, 3.15, -0.64),
            (2.26, 1.97, -2.4), (3.21, 0.53, -3.85), (4.6, -1.11, -4.92), (7.09, -2.9, -5.58),
            (16.67, -4.75, -5.8), (50, -4.75, -5.8), (50.46, -4.57, -3.54), (50.97, -4.03, -1.36),
            (51.55, -3.15, 0.64), (52.26, -1.97, 2.4), (53.21, -0.53, 3.85), (54.6, 1.11, 4.92),
            (57.09, 2.9, 5.58), (66.67, 4.75, 5.8), (100, 4.75, 5.8),
        ],
        // orbit-3 (dot 4): bottom-left ↔ top-right, B-run at 25–41.67 % and 75–91.67 %.
        [
            (0, -4.75, 5.8), (25, -4.75, 5.8), (25.46, -4.57, 3.54), (25.97, -4.03, 1.36),
            (26.55, -3.15, -0.64), (27.26, -1.97, -2.4), (28.21, -0.53, -3.85), (29.6, 1.11, -4.92),
            (32.09, 2.9, -5.58), (41.67, 4.75, -5.8), (75, 4.75, -5.8), (75.46, 4.57, -3.54),
            (75.97, 4.03, -1.36), (76.55, 3.15, 0.64), (77.26, 1.97, 2.4), (78.21, 0.53, 3.85),
            (79.6, -1.11, 4.92), (82.09, -2.9, 5.58), (91.67, -4.75, 5.8), (100, -4.75, 5.8),
        ],
    ]

    private func drawOrbit(into canvas: GraphicsContext, time: Double, alpha: Double) {
        let percent = time.truncatingRemainder(dividingBy: 2.4) / 2.4 * 100
        // The four corner-swap corners sit on the 45 : 55 rectangle around the box's centre.
        let centreX = 9.0
        let centreY = canvasTop + 8.0
        for keys in Self.orbitKeyframes {
            let position = Self.sample(keys, at: percent)
            let rect = CGRect(
                x: centreX + position.x - 2, y: centreY + position.y - 2, width: 4, height: 4)
            canvas.fill(Path(ellipseIn: rect), with: .color(ClaudePalette.orange.opacity(alpha)))
        }
    }

    private static func sample(_ keys: [(Double, Double, Double)], at percent: Double) -> CGPoint {
        guard let first = keys.first, let last = keys.last else { return .zero }
        var previous = first
        for key in keys {
            if key.0 >= percent {
                let span = key.0 - previous.0
                let f = span > 0 ? (percent - previous.0) / span : 0
                return CGPoint(x: previous.1 + (key.1 - previous.1) * f, y: previous.2 + (key.2 - previous.2) * f)
            }
            previous = key
        }
        return CGPoint(x: last.1, y: last.2)
    }
}

/// The curves the loader needs, in one place.
private enum Easing {
    /// Plain ease-in-out for the hand-over cross-fade.
    static func easeInOut(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return clamped < 0.5 ? 2 * clamped * clamped : -1 + (4 - 2 * clamped) * clamped
    }
}

private enum CubicBezier {
    /// CSS `ease` = cubic-bezier(0.25, 0.1, 0.25, 1).
    static func standardEase(_ x: Double) -> Double { solve(x, x1: 0.25, y1: 0.1, x2: 0.25, y2: 1) }

    static func solve(_ x: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        let clamped = min(max(x, 0), 1)
        if clamped == 0 || clamped == 1 { return clamped }

        func axis(_ a: Double, _ b: Double, _ t: Double) -> Double {
            // One axis of a cubic Bézier from 0 to 1 through two control points.
            let mt = 1 - t
            return 3 * mt * mt * t * a + 3 * mt * t * t * b + t * t * t
        }
        func axisSlope(_ a: Double, _ b: Double, _ t: Double) -> Double {
            let mt = 1 - t
            return 3 * mt * mt * a + 6 * mt * t * (b - a) + 3 * t * t * (1 - b)
        }
        // Newton's method on the x axis, bisection as a fallback.
        var t = clamped
        for _ in 0..<8 {
            let error = axis(x1, x2, t) - clamped
            if abs(error) < 1e-6 { return axis(y1, y2, t) }
            let slope = axisSlope(x1, x2, t)
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        var low = 0.0, high = 1.0
        while high - low > 1e-6 {
            t = (low + high) / 2
            if axis(x1, x2, t) < clamped { low = t } else { high = t }
        }
        return axis(y1, y2, t)
    }
}
#endif
