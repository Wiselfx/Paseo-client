#if canImport(UIKit)
import SwiftUI

/// The drawer affordance: three rules, the last one short.
struct UnequalMenu: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            for (y, width) in [(0.1, 1.0), (0.5, 1.0), (0.9, 0.5)] {
                p.move(to: CGPoint(x: 0, y: rect.height * y))
                p.addLine(to: CGPoint(x: rect.width * width, y: rect.height * y))
            }
        }
    }
}

/// Motion timings from the DSH motion table, in one place.
enum ClaudeMotion {
    /// `--dsh-claude-duration-feedback` / reveal / exit.
    static let feedback: Double = 0.12
    /// `--dsh-claude-duration-move`: the height roll on a disclosure.
    static let move: Double = 0.20
    /// The wording swap: 150 ms per half with a 50 ms gap.
    static let swap: Double = 0.15
    /// `--dsh-claude-duration-open`: the overtime badge.
    static let open: Double = 0.25
    /// `--dsh-claude-period-hold` / status sweep.
    static let statusPeriod: Double = 1.5
    /// `--dsh-claude-duration-host-sweep-delay`: the band waits this long after the words appear.
    static let sweepDelay: Double = 0.3
    /// `--dsh-claude-ease-host-sweep`: `steps(48, end)`.
    static let sweepSteps: Int = 48
    /// `--dsh-claude-period-dot-rotate`: a loader motion stands this long before another takes over.
    static let dotRotate: Double = 10
    /// `--dsh-claude-duration-dot-morph`: the hand-over between two loader motions.
    static let dotMorph: Double = 0.48
    /// `WORD_LOCK_MS`: a wording stands for at least a second.
    static let wordLock: Double = 1.0
    /// 10 s of silence before "No response yet".
    static let overtime: Double = 10
    /// `--dsh-claude-duration-rise`: the home greeting rising into place.
    static let rise: Double = 0.5
    /// `--dsh-claude-duration-stagger`: the second entrance starts this much later.
    static let stagger: Double = 0.07
    /// `--dsh-claude-distance-rise`.
    static let riseDistance: CGFloat = 12
    /// `--dsh-claude-blur-enter`.
    static let enterBlur: CGFloat = 3
}

/// "Completed in 4s", "Worked for 2m 10s".
enum DurationText {
    static func completed(_ seconds: TimeInterval) -> String {
        "Completed in \(short(seconds))"
    }

    static func short(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        let minutes = total / 60, rest = total % 60
        if minutes < 60 { return rest == 0 ? "\(minutes)m" : "\(minutes)m \(rest)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// The host caps an open process card at `min(400pt, 50% of height)`; the chat root publishes the
/// screen-derived value so the card doesn't have to guess at its own container.
private struct ClaudeProcessCapKey: EnvironmentKey {
    static let defaultValue: CGFloat = 400
}

extension EnvironmentValues {
    var claudeProcessCap: CGFloat {
        get { self[ClaudeProcessCapKey.self] }
        set { self[ClaudeProcessCapKey.self] = newValue }
    }
}

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

/// 0.5 pt hairline, as the DSH separators are drawn.
struct ClaudeDivider: View {
    var body: some View {
        Rectangle().fill(Palette.divider).frame(height: 0.5)
    }
}

/// A trailing chevron, 12 × 12, turning down while its row is open.
struct ClaudeChevron: View {
    var expanded: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.glyph(.small, weight: .semibold))
            .foregroundStyle(Palette.tertiaryInk)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }
}

/// The trailing chevron the process card's thought/file rows wear (doc 08 §1.3): a 12 × 12 mask
/// of `M6 4l4 4-4 4`, stroke 1.5 with round caps, rotated a quarter turn while the row is open.
struct ClaudeTurnChevron: View {
    var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 6, y: 4))
            path.addLine(to: CGPoint(x: 10, y: 8))
            path.addLine(to: CGPoint(x: 6, y: 12))
        }
        .stroke(
            Palette.tertiaryInk,
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        )
        .frame(width: 12, height: 12)
        .rotationEffect(.degrees(expanded ? 90 : 0))
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: expanded)
        .accessibilityHidden(true)
    }
}

/// Touch has no hover: the summary row's leading seat shows its chevron while the row is open
/// or while a finger is down, and the activity glyph otherwise. The key is injected by
/// `ClaudePressButtonStyle`; it defaults to false everywhere else.
private struct ClaudeRowPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var claudeRowPressed: Bool {
        get { self[ClaudeRowPressedKey.self] }
        set { self[ClaudeRowPressedKey.self] = newValue }
    }
}

/// A plain button style that publishes `isPressed` into the environment so the row's leading
/// seat can follow the finger. No visual change of its own.
struct ClaudePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.claudeRowPressed, configuration.isPressed)
    }
}

/// Rounded card with the 1 pt edge the process column uses.
struct ClaudeCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.cardBorder, lineWidth: 1)
            }
    }
}
#endif
