#if canImport(UIKit)
import SwiftUI

enum CubicBezier {
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
