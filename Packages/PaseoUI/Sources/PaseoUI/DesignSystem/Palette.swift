#if canImport(UIKit)
import SwiftUI
import UIKit

/// The pure-black flag as a UIKit trait: the palette's `UIColor` providers read it from the
/// trait collection, so switching Dark ↔ Pure black redraws live instead of rebuilding the app.
struct PureBlackTrait: UITraitDefinition {
    static let defaultValue = false
    static let identifier = "com.wiselfx.paseoclient.pureBlack"
}

extension UITraitCollection {
    var pureBlack: Bool { self[PureBlackTrait.self] }
}

/// The SwiftUI side of the trait: `RootView` sets `\.pureBlack`, and SwiftUI bridges it into the
/// UIKit trait collections its hosting views see.
struct PureBlackKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    public var pureBlack: Bool {
        get { self[PureBlackKey.self] }
        set { self[PureBlackKey.self] = newValue }
    }
}

extension PureBlackKey: UITraitBridgedEnvironmentKey {
    static func read(from traitCollection: UITraitCollection) -> Bool {
        traitCollection.pureBlack
    }

    static func write(to mutableTraits: inout any UIMutableTraits, value: Bool) {
        mutableTraits[PureBlackTrait.self] = value
    }
}

/// The app's palette (ClaudeUI's tokens extended with the DSH turn tokens; see
/// `docs/research/08-dsh-live-observation.md` §5, which overrides doc 06).
enum Palette {
    /// #141413 in dark, ClaudeUI's warm canvas in light.
    static var background: Color {
        Color(uiColor: UIColor { traits in
            if traits[PureBlackTrait.self] {
                return UIColor(white: 0, alpha: 1)
            }
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 20 / 255, green: 20 / 255, blue: 19 / 255, alpha: 1)
                : UIColor(red: 0.976, green: 0.976, blue: 0.969, alpha: 1)
        })
    }
    static var panel: Color {
        adaptive(light: 1, dark: 31 / 255, pureBlack: 15 / 255)
    }
    /// A lifted gray composer card, ~#262624 in dark.
    static var composer: Color {
        Color(uiColor: UIColor { traits in
            if traits[PureBlackTrait.self] {
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
    static func adaptive(light: Double, dark: Double, pureBlack: Double? = nil) -> Color {
        Color(
            uiColor: UIColor { traits in
                if traits[PureBlackTrait.self] {
                    return UIColor(white: pureBlack ?? dark, alpha: 1)
                }
                return traits.userInterfaceStyle == .dark
                    ? UIColor(white: dark, alpha: 1) : UIColor(white: light, alpha: 1)
            })
    }
    static let orange = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)

    // MARK: DSH tokens

    /// `--dsw-alias-label-primary`: #161616 light / #FDFDFD dark. The ink the whole app paints
    /// text with (`primaryInk` and `shimmerInk` merged in, keeping these values).
    static let ink = Color(
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
            if traits[PureBlackTrait.self] {
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
    /// `#F4F2F3` light / translucent white dark — DSH's `#F4F2F3` / `rgba(255,255,255,0.06)`.
    static let userBubble = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.06)
                : UIColor(red: 244 / 255, green: 242 / 255, blue: 243 / 255, alpha: 1)
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

    // MARK: Diff and selection

    /// A diff line's tint and its sign ink, shared by every diff view and `+N/−N` renderer.
    static let diffAdded = successInk.opacity(0.14)
    static let diffRemoved = failureInk.opacity(0.14)
    static let diffAddedInk = successInk
    static let diffRemovedInk = failureInk
    /// Checkmarks, selected tiles and other "chosen" marks (UX-SPEC §0.1).
    static let selection = Color.blue
    /// Switch and toggle tint.
    static let toggleTint = Color.blue

    /// The appearance swatches the picker draws (Settings and `WelcomeView` share them).
    enum Swatch {
        static let light = Color(white: 0.97)
        static let dark = Color(white: 0.08)
        static let pureBlack = Color(white: 0)
    }
}

/// The pre-R2 name. Delete once every call site reads `Palette`.
typealias ClaudePalette = Palette
#endif
