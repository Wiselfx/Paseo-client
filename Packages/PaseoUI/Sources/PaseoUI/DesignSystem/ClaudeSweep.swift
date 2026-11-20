#if canImport(UIKit)
import SwiftUI

/// The highlight band the running words sweep under (doc 08 §3.4): a masked, shimmer-ink copy of
/// the glyph run reveals under a soft-edged diagonal window that crosses once per 1.5 s, stepped in
/// 48 places, 300 ms after the words appear, holding still for the last third of the period.
/// The wash is never a translucent fill behind the words — only the tinted glyphs show.
enum ClaudeSweep {
    /// The stepped 0...<1 sweep position, or nil while the band rests (last third of the period).
    static func phase(startedAt start: Date, at date: Date) -> Double? {
        let elapsed = date.timeIntervalSince(start) - ClaudeMotion.sweepDelay
        guard elapsed >= 0 else { return nil }
        let cycle = elapsed.truncatingRemainder(dividingBy: ClaudeMotion.statusPeriod)
        let active = ClaudeMotion.statusPeriod * (2.0 / 3.0) // 1 s of motion, 0.5 s of rest
        guard cycle < active else { return nil }
        let raw = cycle / active
        return (raw * Double(ClaudeMotion.sweepSteps)).rounded(.down) / Double(ClaudeMotion.sweepSteps)
    }

    /// The mask: a soft-edged window sliding left → right across about one label width and a half.
    /// The 105° tilt is approximated with a gentle downward axis; the geometry is not measured.
    static func windowGradient(phase: Double) -> LinearGradient {
        let cx = -0.25 + 1.5 * phase
        func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
        return LinearGradient(
            stops: [
                .init(color: .clear, location: clamp(cx - 0.4)),
                .init(color: .black, location: clamp(cx - 0.1)),
                .init(color: .black, location: clamp(cx + 0.1)),
                .init(color: .clear, location: clamp(cx + 0.4)),
            ],
            startPoint: UnitPoint(x: 0, y: 0),
            endPoint: UnitPoint(x: 1, y: 0.26))
    }
}
#endif
