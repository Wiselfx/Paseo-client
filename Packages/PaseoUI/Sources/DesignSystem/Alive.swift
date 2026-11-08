import SwiftUI

/// Text with a light sweeping across it: the "I'm working" signal.
public struct ShimmerText: View {
    var text: String
    var font: Font
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ text: String, font: Font = Typeset.chrome) {
        self.text = text
        self.font = font
    }

    public var body: some View {
        let base = Text(text).font(font).foregroundStyle(Palette.secondaryInk)
        if reduceMotion {
            base
        } else {
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                base.overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: max(0, phase - 0.25)),
                            .init(color: Palette.ink.opacity(0.9), location: phase),
                            .init(color: .clear, location: min(1, phase + 0.25)),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .mask(Text(text).font(font))
                }
            }
        }
    }
}

/// The playful words shown while an agent works. Stable per turn and step, so a row doesn't
/// flicker between words on every re-render, and rotates every few seconds.
public enum Quips {
    public static let working = [
        "Pondering", "Tinkering", "Noodling", "Percolating", "Mulling", "Rummaging", "Untangling",
        "Sleuthing", "Whittling", "Simmering", "Assembling", "Calibrating", "Spelunking",
        "Puzzling", "Brewing", "Sketching", "Wrangling", "Tidying", "Scheming", "Distilling",
        "Hatching", "Conjuring", "Fiddling", "Plotting", "Cogitating", "Marinating",
    ]

    /// A word for `seed` (for example a turn id) that changes every `period` seconds.
    public static func word(seed: String, at date: Date, period: TimeInterval = 3.5) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let tick = UInt64(max(0, date.timeIntervalSinceReferenceDate / period))
        return working[Int((hash &+ tick) % UInt64(working.count))] + "…"
    }
}

/// A rotating, shimmering quip. Use while something runs.
public struct WorkingLabel: View {
    var seed: String
    public init(seed: String) { self.seed = seed }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 3.5)) { context in
            ShimmerText(Quips.word(seed: seed, at: context.date))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.35), value: Quips.word(seed: seed, at: context.date))
        }
    }
}

/// "Completed in 4s", "Worked for 2m 10s".
public enum DurationText {
    public static func completed(_ seconds: TimeInterval) -> String {
        "Completed in \(short(seconds))"
    }

    public static func short(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        let minutes = total / 60, rest = total % 60
        if minutes < 60 { return rest == 0 ? "\(minutes)m" : "\(minutes)m \(rest)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
