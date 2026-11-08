import SwiftUI
import UIKit

/// Colors. Warm neutrals with one clay accent. Every color adapts to light and dark.
public enum Palette {
    public static let background = adaptive(0xFAF9F5, 0x1F1E1D)
    /// Cards, tool calls, the composer.
    public static let surface = adaptive(0xFFFFFF, 0x262624)
    public static let surfaceRaised = adaptive(0xF5F4EF, 0x30302E)
    public static let hairline = adaptiveAlpha(light: (0, 0.10), dark: (1, 0.10))
    public static let ink = adaptive(0x1F1E1D, 0xECEAE4)
    public static let secondaryInk = adaptive(0x73726C, 0x9C9A92)
    public static let tertiaryInk = adaptive(0xA3A29B, 0x6E6D68)
    public static let accent = Color(hex: 0xD97757)
    public static let userBubble = adaptive(0xEFEDE5, 0x30302E)
    public static let codeBackground = adaptive(0xF5F4EF, 0x1A1918)
    public static let success = adaptive(0x3B8B4F, 0x6FBF7E)
    public static let failure = adaptive(0xC0453A, 0xE5675B)
    public static let diffAdded = adaptiveAlpha(light: (0x3B8B4F, 0.14), dark: (0x6FBF7E, 0.16))
    public static let diffRemoved = adaptiveAlpha(light: (0xC0453A, 0.12), dark: (0xE5675B, 0.16))

    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    /// `(rgb, alpha)` pairs; rgb `0` or `1` mean black or white.
    static func adaptiveAlpha(light: (UInt32, CGFloat), dark: (UInt32, CGFloat)) -> Color {
        func color(_ pair: (UInt32, CGFloat)) -> UIColor {
            switch pair.0 {
            case 0: UIColor(white: 0, alpha: pair.1)
            case 1: UIColor(white: 1, alpha: pair.1)
            default: UIColor(hex: pair.0).withAlphaComponent(pair.1)
            }
        }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) })
    }
}

/// Type. Serif for what the agent says, system sans for chrome, mono for code.
public enum Typeset {
    public static let serifName = "Newsreader16pt-Regular"

    /// Call once at launch so the bundled serif is available everywhere.
    @MainActor public static func registerFonts() { ClaudeFontResources.register() }

    public static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(serifName, size: size, relativeTo: style)
    }

    public static let prose = serif(18)
    public static let proseSecondary = serif(16)
    public static let chrome = Font.system(size: 15)
    public static let chromeEmphasis = Font.system(size: 15, weight: .medium)
    public static let caption = Font.system(size: 13)
    public static let mono = Font.system(size: 13.5, design: .monospaced)
    public static let monoSmall = Font.system(size: 12.5, design: .monospaced)

    /// Markdown theme for assistant prose.
    public static var markdown: ClaudeMarkdownTheme {
        var theme = ClaudeMarkdownTheme(serifName: serifName, bodySize: 18)
        theme.foreground = Palette.ink
        theme.link = Palette.accent
        theme.codeBackground = Palette.codeBackground
        theme.blockSpacing = 14
        return theme
    }
}

/// Spacing and shape, so screens line up on the same rails.
public enum Metrics {
    public static let gutter: CGFloat = 20
    public static let cardRadius: CGFloat = 16
    public static let innerRadius: CGFloat = 12
    public static let bubbleRadius: CGFloat = 20
    public static let turnSpacing: CGFloat = 28
    public static let stepSpacing: CGFloat = 10
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
