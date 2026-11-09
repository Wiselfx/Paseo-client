#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The quiet context ring: a thin arc, track in `chip`, ramped colour by percent
/// (green → amber → red). No numbers in the ring itself; the reading lives beside it.
/// Reduce Motion renders the final arc without interpolating.
struct ClaudeMeterRing: View {
    /// 0…100, already clamped by the caller.
    let percent: Double
    var size: CGFloat = 16
    var lineWidth: CGFloat = 1.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(percent, 0), 100) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ClaudePalette.chip, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(clamped / 100))
                .stroke(
                    Self.rampColor(clamped),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: clamped)
        .accessibilityHidden(true)
    }

    /// green → amber → red, green below ~40 %, red from ~80 % on, continuous between.
    static func rampColor(_ percent: Double) -> Color {
        let fraction = min(max(percent, 0), 100) / 100
        return Color(hue: 0.333 * (1 - fraction), saturation: 0.72, brightness: 0.82)
    }
}

/// A thin progress bar for the sidebar's usage lines and the reports sheet's window rows:
/// track in `chip`, fill ramped by percent, rounded ends.
struct ClaudeUsageBar: View {
    let percent: Double
    var width: CGFloat = 56

    private var clamped: Double { min(max(percent, 0), 100) }

    var body: some View {
        Capsule()
            .fill(ClaudePalette.chip)
            .frame(width: width, height: 3)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(ClaudeMeterRing.rampColor(clamped))
                    .frame(width: width * CGFloat(clamped / 100), height: 3)
            }
            .accessibilityHidden(true)
    }
}

/// Human wording for a window reset: "resets 3h" / "resets 2d" / "resets now".
enum ClaudeUsageResets {
    static func short(afterISO date: String?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        guard let target = PaseoDate.parse(date) else { return nil }
        let seconds = Int(target.timeIntervalSince(now))
        if seconds <= 0 { return "resets now" }
        if seconds < 60 { return "resets <1m" }
        let minutes = seconds / 60
        if minutes < 60 { return "resets \(minutes)m" }
        let hours = minutes / 60
        if hours < 48 { return "resets \(hours)h" }
        return "resets \(hours / 24)d"
    }
}
#endif
