#if canImport(UIKit)
import SwiftUI

/// The app-wide typography: Anthropic Sans for the interface, Anthropic Serif for prose and
/// display lines, Anthropic Mono for code and tool output. Every face keeps Dynamic Type.
public struct ClaudeTypography: Sendable {
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
}

/// ClaudeUI's palette, extended with the tokens the DSH turn layout asks for
/// (`docs/research/06-dsh-ux-spec.md` §1.9).
enum ClaudePalette {
    /// #141413 in dark, ClaudeUI's warm canvas in light.
    static let background = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 20 / 255, green: 20 / 255, blue: 19 / 255, alpha: 1)
                : UIColor(red: 0.976, green: 0.976, blue: 0.969, alpha: 1)
        })
    /// The drawer sits a touch darker than the content panel in dark mode.
    static let sidebarBackground = adaptive(light: 0.96, dark: 16 / 255)
    static let codeBackground = adaptive(light: 0.98, dark: 0.04)
    static let panel = adaptive(light: 1, dark: 31 / 255)
    /// A lifted gray composer card, ~#262624 in dark.
    static let composer = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 38 / 255, green: 38 / 255, blue: 36 / 255, alpha: 1)
                : UIColor(white: 0.99, alpha: 1)
        })
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
    static func adaptive(light: Double, dark: Double) -> Color {
        Color(
            uiColor: UIColor {
                $0.userInterfaceStyle == .dark ? UIColor(white: dark, alpha: 1) : UIColor(white: light, alpha: 1)
            })
    }
    static let orange = Color(red: 0.80, green: 0.36, blue: 0.23)

    // MARK: DSH tokens

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
    static let userBubble = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.06) : UIColor(white: 0.92, alpha: 1)
        })
    /// `--dsh-claude-chip`, the hover/pressed plate.
    static let chip = adaptive(light: 0.965, dark: 0.14)
    /// `--dsw-alias-state-warn-label`, the awaiting-input dot and the overtime badge.
    static let warning = Color(red: 0.980, green: 0.698, blue: 0.098)
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
    /// `--dsh-claude-duration-feedback` / reveal / exit.
    static let feedback: Double = 0.12
    /// `--dsh-claude-duration-move`: the height roll on a disclosure.
    static let move: Double = 0.20
    /// `--dsh-claude-duration-roll`: the counted digits.
    static let roll: Double = 0.16
    /// The wording swap: 150 ms per half with a 50 ms gap.
    static let swap: Double = 0.15
    /// `--dsh-claude-duration-open`: the overtime badge.
    static let open: Double = 0.25
    /// `--dsh-claude-period-hold` / status sweep.
    static let statusPeriod: Double = 1.5
    /// `WORD_LOCK_MS`: a wording stands for at least a second.
    static let wordLock: Double = 1.0
    /// `TICK_MS`: the status line's clock.
    static let tick: Double = 0.25
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

/// Rounded card with the 1 pt edge the process column uses.
struct ClaudeCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ClaudePalette.panel, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
            }
    }
}
#endif
