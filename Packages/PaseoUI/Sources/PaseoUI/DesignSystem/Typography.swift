#if canImport(UIKit)
import SwiftUI
import Synchronization
import UIKit

extension Font {
    /// The one way to get a text font.
    static func paseo(_ role: TextRole, weight: Font.Weight? = nil) -> Font {
        Typography.font(role, weight: weight ?? role.bakedWeight)
    }

    /// The one way to get an icon font.
    static func glyph(_ size: GlyphSize, weight: Font.Weight = .regular) -> Font {
        Typography.glyph(size, weight: weight)
    }
}
/// Face and font resolution: the bundled faces are resolved once, fonts are cached by role,
/// and the fallback keeps the requested size (scaled through `UIFontMetrics`, never a
/// `.system(style)` that would lose it).
enum Typography {
    /// Claude iOS's chat body (V5): assistant prose, your bubbles and the composer all sit at
    /// 17 pt, and everything around them is measured from it. Outside prose, name this, not
    /// `ClaudeTypography`.
    static let chatBodySize: CGFloat = 17

    /// The registered face for each family, resolved once after `register()`.
    ///
    /// Sans is Inter, serif is Newsreader, mono is JetBrains Mono: the open set, each with real
    /// weights and real italics. The system face is the only fallback (`scaledSystem`).
    /// `Upstream: dsh-claude-style-reference/README.en.md "Fonts"`.
    static let serifName: String? = {
        ClaudeFontResources.register()
        return ClaudeFontResources.isAvailable(ClaudeFontResources.newsreader)
            ? ClaudeFontResources.newsreader : nil
    }()
    static let sansName: String? = {
        ClaudeFontResources.register()
        return ClaudeFontResources.isAvailable(ClaudeFontResources.inter)
            ? ClaudeFontResources.inter : nil
    }()
    static let monoName: String? = {
        ClaudeFontResources.register()
        return ClaudeFontResources.isAvailable(ClaudeFontResources.jetBrainsMono)
            ? ClaudeFontResources.jetBrainsMono : nil
    }()

    /// The app reads in Apple's own faces: New York (serif), SF Pro (sans) and SF Mono (mono), through
    /// the system font API (`scaledSystem`). They are free to use on Apple platforms, need no font
    /// files or registration, size optically by themselves and follow Dynamic Type. No bundled family
    /// is chosen, so this answers nil for every family (the bundled files stay in the repo, unused).
    static func baseName(_ family: TextRole.Face) -> String? { nil }

    /// The serif face name the Markdown theme wants, resolved once.
    static let resolvedSerifName: String = ClaudeFontResources.newsreader

    private struct Key: Hashable {
        let role: TextRole
        let weight: Font.Weight?
    }

    private static let fonts = Mutex<[Key: Font]>([:])

    static func font(_ role: TextRole, weight: Font.Weight?) -> Font {
        let key = Key(role: role, weight: weight)
        return fonts.withLock { cache in
            if let hit = cache[key] { return hit }
            let font = make(role: role, weight: weight ?? .regular)
            cache[key] = font
            return font
        }
    }

    /// A role's font: the family's real face at the role's size, from the one builder prose uses.
    private static func make(role: TextRole, weight: Font.Weight) -> Font {
        ProseFonts.font(
            role.face, size: role.size, relativeTo: role.relativeTo, weight: weight, italic: false)
    }

    private struct GlyphKey: Hashable {
        let size: GlyphSize
        let weight: Font.Weight
    }

    private static let glyphs = Mutex<[GlyphKey: Font]>([:])

    static func glyph(_ size: GlyphSize, weight: Font.Weight) -> Font {
        let key = GlyphKey(size: size, weight: weight)
        return glyphs.withLock { cache in
            if let hit = cache[key] { return hit }
            let font = scaledSystem(size: size.size, relativeTo: .body, design: .default, weight: weight)
            cache[key] = font
            return font
        }
    }

    /// The fallback face, scaled through `UIFontMetrics` so the role's size survives.
    static func scaledSystem(
        size: CGFloat, relativeTo style: Font.TextStyle, design: UIFontDescriptor.SystemDesign,
        weight: Font.Weight, italic: Bool = false
    ) -> Font {
        let system = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        var descriptor = system.fontDescriptor.withDesign(design) ?? system.fontDescriptor
        if italic { descriptor = descriptor.withSymbolicTraits(.traitItalic) ?? descriptor }
        let face = UIFont(descriptor: descriptor, size: size)
        return Font(UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: face))
    }

    /// The same face and size a role's `Font` draws with, as a `UIFont`, for the UIKit views that
    /// have to set a font themselves (the composer's text view). Scaled through `UIFontMetrics`
    /// for the role's text style, so `adjustsFontForContentSizeCategory` keeps working.
    static func uiFont(_ role: TextRole, weight: Font.Weight = .regular) -> UIFont {
        let resolvedWeight = role.bakedWeight ?? weight
        let system = UIFont.systemFont(ofSize: role.size, weight: resolvedWeight.uiWeight)
        let base: UIFont
        switch role.face {
        case .sans:
            base = system
        case .serif:
            base = system.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: role.size) } ?? system
        case .mono:
            base = UIFont.monospacedSystemFont(ofSize: role.size, weight: resolvedWeight.uiWeight)
        }
        return UIFontMetrics(forTextStyle: role.relativeTo.uiTextStyle).scaledFont(for: base)
    }
}
extension Font.Weight {
    var uiWeight: UIFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
extension DynamicTypeSize {
    /// `self` moved along the size ladder by `steps`, clamped to the ends.
    public func shifted(by steps: Int) -> DynamicTypeSize {
        guard steps != 0 else { return self }
        let ladder = DynamicTypeSize.allCases
        guard let index = ladder.firstIndex(of: self) else { return self }
        let target = min(max(index + steps, 0), ladder.count - 1)
        return ladder[target]
    }
}
/// The code text size step (S = −1, M = 0, L = +1, XL = +2), set by `RootView`. Code containers
/// apply it with `.dynamicTypeSize(current shifted by codeSizeStep)`.
extension EnvironmentValues {
    @Entry public var codeSizeStep = 0
}
extension View {
    /// Scale a code container by the Code size setting on top of the content Dynamic Type size.
    func codeTypeScale() -> some View {
        modifier(CodeTypeScale())
    }
}
#endif
