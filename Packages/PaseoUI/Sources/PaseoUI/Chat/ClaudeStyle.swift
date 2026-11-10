#if canImport(UIKit)
import SwiftUI

/// The app-wide typography: Anthropic Sans for the interface, Anthropic Serif for prose and
/// display lines, Anthropic Mono for code and tool output. Every face keeps Dynamic Type.
public struct ClaudeTypography: Sendable {
    /// Claude iOS's chat body (V5): assistant prose, your bubbles and the composer all sit at
    /// 17 pt, and everything around them is measured from it.
    public static let chatBodySize: CGFloat = 17

    public static let anthropicSans = "AnthropicSansWebVariable-TextRegular"
    public static let anthropicSerif = "AnthropicSerifWebVariable-TextRegular"
    public static let anthropicMono = "AnthropicMonoWebWeb-Regular"
    public static let newsreader = "Newsreader16pt-Regular"

    public var serifName: String
    public var sansName: String
    public var monoName: String

    public init(
        serifName: String = ClaudeTypography.anthropicSerif,
        sansName: String = ClaudeTypography.anthropicSans,
        monoName: String = ClaudeTypography.anthropicMono
    ) {
        self.serifName = serifName
        self.sansName = sansName
        self.monoName = monoName
    }

    /// Assistant prose, greeting, sidebar title, headings.
    public func serif(
        _ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular
    ) -> Font {
        let size = size * ClaudeTextScale.contentMultiplier()
        if ClaudeFontResources.isAvailable(serifName) {
            return apply(weight, to: .custom(serifName, size: size, relativeTo: style))
        }
        if ClaudeFontResources.isAvailable(ClaudeTypography.newsreader) {
            return apply(weight, to: .custom(ClaudeTypography.newsreader, size: size, relativeTo: style))
        }
        return .system(style, design: .serif, weight: weight)
    }

    /// UI text, buttons, composer, sidebar rows.
    public func sans(
        _ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular
    ) -> Font {
        guard ClaudeFontResources.isAvailable(sansName) else {
            return .system(style, design: .default, weight: weight)
        }
        return apply(weight, to: .custom(sansName, size: size, relativeTo: style))
    }

    /// Code, tool output, diffs.
    public func mono(
        _ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular
    ) -> Font {
        let size = size * ClaudeTextScale.codeMultiplier()
        guard ClaudeFontResources.isAvailable(monoName) else {
            return .system(style, design: .monospaced, weight: weight)
        }
        return apply(weight, to: .custom(monoName, size: size, relativeTo: style))
    }

    /// The name the Markdown theme needs; Anthropic Serif with Newsreader as the fallback.
    public var resolvedSerifName: String {
        if ClaudeFontResources.isAvailable(serifName) { return serifName }
        if ClaudeFontResources.isAvailable(ClaudeTypography.newsreader) { return ClaudeTypography.newsreader }
        return serifName
    }

    private func apply(_ weight: Font.Weight, to font: Font) -> Font {
        font.weight(weight)
    }
}

/// Keys shared by the app's composition root and the in-app settings sheet.
public enum PaseoSettingsKeys {
    public static let appearance = "paseo.appearance"
    public static let yourName = "paseo.yourName"
    public static let haptics = "paseo.haptics"
    public static let mascot = "paseo.mascot.enabled"
}

/// ClaudeUI's palette, extended with the tokens the DSH turn layout asks for
/// (`docs/research/08-dsh-live-observation.md` §5 — that document overrides doc 06).
enum ClaudePalette {
    /// #141413 in dark, ClaudeUI's warm canvas in light.
    static var background: Color {
        Color(uiColor: UIColor { traits in
            if ClaudeAppearance.pureBlackActive {
                return UIColor(white: 0, alpha: 1)
            }
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 20 / 255, green: 20 / 255, blue: 19 / 255, alpha: 1)
                : UIColor(red: 0.976, green: 0.976, blue: 0.969, alpha: 1)
        })
    }
    /// The drawer sits a touch darker than the content panel in dark mode.
    static var sidebarBackground: Color {
        adaptive(light: 0.96, dark: 16 / 255, pureBlack: 7 / 255)
    }
    static var codeBackground: Color {
        adaptive(light: 0.98, dark: 0.04, pureBlack: 0.02)
    }
    static var panel: Color {
        adaptive(light: 1, dark: 31 / 255, pureBlack: 15 / 255)
    }
    /// A lifted gray composer card, ~#262624 in dark.
    static var composer: Color {
        Color(uiColor: UIColor { traits in
            if ClaudeAppearance.pureBlackActive {
                return UIColor(white: 18 / 255, alpha: 1)
            }
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 38 / 255, green: 38 / 255, blue: 36 / 255, alpha: 1)
                : UIColor(white: 0.99, alpha: 1)
        })
    }
    static let composerBorder = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 0.79, alpha: 1)
        })
    static let secondary = Color(white: 0.56)
    /// Warm off-white in dark, ClaudeUI's near-black in light.
    static let ink = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.949, green: 0.937, blue: 0.914, alpha: 1)
                : UIColor(white: 0.13, alpha: 1)
        })
    static func adaptive(light: Double, dark: Double, pureBlack: Double? = nil) -> Color {
        Color(
            uiColor: UIColor { traits in
                if ClaudeAppearance.pureBlackActive {
                    return UIColor(white: pureBlack ?? dark, alpha: 1)
                }
                return traits.userInterfaceStyle == .dark
                    ? UIColor(white: dark, alpha: 1) : UIColor(white: light, alpha: 1)
            })
    }
    static let orange = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)

    // MARK: DSH tokens

    /// `--dsw-alias-label-primary`: #161616 light / #FDFDFD dark. The ink DSH paints prose and
    /// turn content with; shared tokens stay `ink` (chrome) — this one is split from it.
    static let primaryInk = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 253 / 255, green: 253 / 255, blue: 253 / 255, alpha: 1)
                : UIColor(red: 22 / 255, green: 22 / 255, blue: 22 / 255, alpha: 1)
        })
    /// `--dsw-alias-label-shimmer`: the sweep band's tint, the ink colour, never the accent.
    static let shimmerInk = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 253 / 255, green: 253 / 255, blue: 253 / 255, alpha: 1)
                : UIColor(red: 22 / 255, green: 22 / 255, blue: 22 / 255, alpha: 1)
        })
    /// The prose link colour, #184F95 light / #8AB4F8 dark (`--dsh-claude-link`).
    static let proseLink = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 138 / 255, green: 180 / 255, blue: 248 / 255, alpha: 1)
                : UIColor(red: 24 / 255, green: 79 / 255, blue: 149 / 255, alpha: 1)
        })
    /// The code-block surface: #FFFFFF light / #212121 dark (`--dsw-alias-markdown-code-block`).
    static var codeSurface: Color {
        Color(uiColor: UIColor { traits in
            if ClaudeAppearance.pureBlackActive {
                return UIColor(white: 17 / 255, alpha: 1)
            }
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 33 / 255, green: 33 / 255, blue: 33 / 255, alpha: 1)
                : UIColor(white: 1, alpha: 1)
        })
    }
    /// `--dsh-claude-inline-code-bg`: rgba(6,6,6,0.05) light / rgba(255,255,255,0.05) dark.
    static let inlineCodeFill = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.05)
                : UIColor(red: 6 / 255, green: 6 / 255, blue: 6 / 255, alpha: 0.05)
        })
    /// The blockquote's wash: rgba(20,20,19,0.04) light / rgba(250,249,245,0.06) dark.
    static let quoteWash = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 250 / 255, green: 249 / 255, blue: 245 / 255, alpha: 0.06)
                : UIColor(red: 20 / 255, green: 20 / 255, blue: 19 / 255, alpha: 0.04)
        })
    /// `--dsw-alias-label-secondary`: #70686A / #BEB6B8.
    static let secondaryInk = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.745, green: 0.714, blue: 0.722, alpha: 1)
                : UIColor(red: 0.439, green: 0.408, blue: 0.416, alpha: 1)
        })
    /// `--dsw-alias-label-tertiary`: #91888A / #9C9395.
    static let tertiaryInk = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.612, green: 0.576, blue: 0.584, alpha: 1)
                : UIColor(red: 0.569, green: 0.533, blue: 0.541, alpha: 1)
        })
    /// `--dsw-alias-label-caption`: #B2ACAD / #776F71.
    static let captionInk = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.467, green: 0.435, blue: 0.443, alpha: 1)
                : UIColor(red: 0.698, green: 0.675, blue: 0.678, alpha: 1)
        })
    /// `--dsh-claude-divider`, drawn at 0.5 pt.
    static let divider = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.06) : UIColor(white: 22 / 255, alpha: 0.05)
        })
    /// `--dsw-alias-border-l1` card edge: #E9E9E9 / translucent white highlight.
    static let cardBorder = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.09) : UIColor(white: 233 / 255, alpha: 1)
        })
    /// `#F0EFEC` light / translucent white 6 % dark (OCU §12.7).
    static let userBubble = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.06)
                : UIColor(red: 240 / 255, green: 239 / 255, blue: 236 / 255, alpha: 1)
        })
    /// `--dsh-claude-chip`, the hover/pressed plate.
    static let chip = adaptive(light: 0.965, dark: 0.14)
    /// `--dsw-alias-state-warn-label`: #DD8629 both themes.
    static let warning = Color(red: 221 / 255, green: 134 / 255, blue: 41 / 255)
    /// The unread / finished-in-background dot.
    static let unread = Color(red: 0.165, green: 0.471, blue: 0.839)
    static let failureInk = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.898, green: 0.404, blue: 0.357, alpha: 1)
                : UIColor(red: 0.753, green: 0.271, blue: 0.227, alpha: 1)
        })
    static let successInk = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.435, green: 0.749, blue: 0.494, alpha: 1)
                : UIColor(red: 0.231, green: 0.545, blue: 0.310, alpha: 1)
        })
}

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
    /// Official duration tokens (`06:1017`): fast 60, snap 120, base 200, sheet 300, slow 450 ms.
    static let fast: Double = 0.06
    static let snap: Double = 0.12
    static let base: Double = 0.2
    static let sheet: Double = 0.3
    static let slow: Double = 0.45
    /// `--dsh-claude-duration-feedback` / reveal / exit.
    static let feedback = snap
    /// `--dsh-claude-duration-move`: the height roll on a disclosure.
    static let move = base
    /// `--dsh-claude-duration-roll`: the counted digits.
    static let roll: Double = 0.16
    /// The wording swap: the status line's enter/exit pair (OCU §12.22).
    static let swap: Double = 0.24
    /// `--dsh-claude-duration-open`: the overtime badge.
    static let open = sheet
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
    /// `TICK_MS`: the status line's clock.
    static let tick: Double = 0.25
    /// 10 s of silence before "No response yet".
    static let overtime: Double = 10
    /// `--dsh-claude-duration-rise`: the home greeting rising into place.
    static let rise = slow
    /// `--dsh-claude-duration-stagger`: the second entrance starts this much later.
    static let stagger: Double = 0.07
    /// `--dsh-claude-distance-rise`.
    static let riseDistance: CGFloat = 12
    /// `--dsh-claude-blur-enter`.
    static let enterBlur: CGFloat = 3
}

/// Official easing tokens (`06:366-368`). UX-SPEC §0.4 keeps every animation critically damped,
/// so the OCU overshoot easing is deliberately not adopted.
enum ClaudeEasing {
    /// `cubic-bezier(.165,.84,.44,1)`.
    static func out(duration: Double) -> Animation {
        .timingCurve(0.165, 0.84, 0.44, 1, duration: duration)
    }

    /// `cubic-bezier(.32,.72,0,1)`.
    static func snap(duration: Double) -> Animation {
        .timingCurve(0.32, 0.72, 0, 1, duration: duration)
    }
}

/// The official radius scale (`06:1010,1016`; `v2/03:84-85`): controls 8, cards 12, bubbles 18,
/// code 12, composers 14, panels 10.
enum ClaudeRadius {
    static let control: CGFloat = 8
    static let card: CGFloat = 12
    static let bubble: CGFloat = 18
    static let code: CGFloat = 12
    static let composer: CGFloat = 14
    static let panel: CGFloat = 10
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
        Rectangle().fill(ClaudePalette.divider).frame(height: 0.5)
    }
}

/// A trailing chevron, 12 × 12, turning down while its row is open.
struct ClaudeChevron: View {
    var expanded: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(ClaudePalette.tertiaryInk)
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
            ClaudePalette.tertiaryInk,
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        )
        .frame(width: 12, height: 12)
        .rotationEffect(.degrees(expanded ? 90 : 0))
        .animation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.feedback), value: expanded)
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
            .background(ClaudePalette.panel, in: .rect(cornerRadius: ClaudeRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: ClaudeRadius.card).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
            }
    }
}
#endif
