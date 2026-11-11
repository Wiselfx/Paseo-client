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
    /// The chat canvas: #151515 in dark, #FCFCFB in light (OCU §12.4, §12.5).
    static var background: Color {
        Color(uiColor: UIColor { traits in
            if traits[PureBlackTrait.self] {
                return UIColor(white: 0, alpha: 1)
            }
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 21 / 255, green: 21 / 255, blue: 21 / 255, alpha: 1)
                : UIColor(red: 252 / 255, green: 252 / 255, blue: 251 / 255, alpha: 1)
        })
    }
    /// The sidebar's canvas, one step below the chat: #0B0B0B in dark, #F9F9F7 in light
    /// (OCU §12.4, §12.5).
    static var sidebar: Color {
        Color(uiColor: UIColor { traits in
            if traits[PureBlackTrait.self] {
                return UIColor(white: 7 / 255, alpha: 1)
            }
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 11 / 255, green: 11 / 255, blue: 11 / 255, alpha: 1)
                : UIColor(red: 249 / 255, green: 249 / 255, blue: 247 / 255, alpha: 1)
        })
    }
    /// Cards: #FFFFFF in light, #1A1A19 in dark (OCU §12.4).
    static var panel: Color {
        Color(uiColor: UIColor { traits in
            if traits[PureBlackTrait.self] {
                return UIColor(white: 15 / 255, alpha: 1)
            }
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 26 / 255, green: 26 / 255, blue: 25 / 255, alpha: 1)
                : UIColor(white: 1, alpha: 1)
        })
    }
    /// A lifted gray composer card, #20201F in dark (OCU §12.4).
    static var composer: Color {
        Color(uiColor: UIColor { traits in
            if traits[PureBlackTrait.self] {
                return UIColor(white: 18 / 255, alpha: 1)
            }
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 32 / 255, green: 32 / 255, blue: 31 / 255, alpha: 1)
                : UIColor(white: 0.99, alpha: 1)
        })
    }
    static let composerBorder = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 0.79, alpha: 1)
        })
    /// The composer's lift in light: black at 6 % (E1 §4). In dark the card is lighter than the
    /// canvas already, and a black shadow under it would just muddy the edge.
    static let composerShadow = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(white: 0, alpha: 0) : UIColor(white: 0, alpha: 0.06)
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

    /// The ink the whole app paints text with: #0B0B0B light / #F0EFEC dark (OCU §12.1).
    static let ink = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 240 / 255, green: 239 / 255, blue: 236 / 255, alpha: 1)
                : UIColor(red: 11 / 255, green: 11 / 255, blue: 11 / 255, alpha: 1)
        })
    /// The prose link colour, the accent blue: #184F95 light / #6DA7EC dark (OCU §12.2).
    static let proseLink = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 109 / 255, green: 167 / 255, blue: 236 / 255, alpha: 1)
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
    /// Secondary label: #52514E light / #C3C2B7 dark (OCU §12.1).
    static let secondaryInk = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 195 / 255, green: 194 / 255, blue: 183 / 255, alpha: 1)
                : UIColor(red: 82 / 255, green: 81 / 255, blue: 78 / 255, alpha: 1)
        })
    /// Tertiary label: #898781 in both modes (OCU §12.1).
    static let tertiaryInk = Color(red: 137 / 255, green: 135 / 255, blue: 129 / 255)
    /// `--dsw-alias-label-caption`: #B2ACAD / #776F71.
    static let captionInk = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.467, green: 0.435, blue: 0.443, alpha: 1)
                : UIColor(red: 0.698, green: 0.675, blue: 0.678, alpha: 1)
        })
    /// 10 % black in light / 10 % white in dark, drawn at 0.5 pt (OCU §12.6).
    static let divider = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 0, alpha: 0.10)
        })
    /// Card edge: 10 % black in light / 10 % white in dark (OCU §12.6).
    static let cardBorder = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 0, alpha: 0.10)
        })
    /// #F0EFEC light / translucent white 6 % dark (OCU §12.7).
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
#endif
