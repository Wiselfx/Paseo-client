#if canImport(UIKit)
import SwiftUI
import Synchronization
import UIKit

/// A text role: one face, one size and one Dynamic Type style, resolved once.
///
/// Views never name a size. Weight is applied on top of the role, except `headline`, which
/// carries its own semibold.
enum TextRole: Hashable, Sendable {
    /// Serif 28: sidebar "Paseo", hero lines.
    case largeTitle
    /// Serif 20: chat header title, sheet hero titles.
    case title
    /// Serif 14: the work group's summary line and other process headings.
    case processTitle
    /// Serif 13: a tool row's title and the opened reasoning text.
    case process
    /// Sans 17 semibold: section and row titles that lead.
    case headline
    /// Sans 17: chat body, composer, settings rows.
    case body
    /// Sans 15: secondary rows, buttons, chips.
    case callout
    /// Sans 13: metadata, captions under rows.
    case footnote
    /// Sans 12: small metadata.
    case caption
    /// Sans 11: badges, pills, counters.
    case caption2
    /// Mono 13: code blocks, tool output, diffs.
    case code
    /// Mono 12: dense code (gutters, chips).
    case codeSmall
    /// Mono 11: line numbers, tiny mono labels.
    case codeCaption
    /// Serif 34: the home hero greeting.
    case hero

    /// The bundled face family this role reads in.
    enum Face: Sendable { case serif, sans, mono }

    var face: Face {
        switch self {
        case .largeTitle, .title, .processTitle, .process, .hero: .serif
        case .code, .codeSmall, .codeCaption: .mono
        case .headline, .body, .callout, .footnote, .caption, .caption2: .sans
        }
    }

    var size: CGFloat {
        switch self {
        case .largeTitle: 28
        case .title: 20
        case .processTitle: 14
        case .process: 13
        case .headline, .body: 17
        case .callout: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        case .code: 13
        case .codeSmall: 12
        case .codeCaption: 11
        case .hero: 34
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title3
        case .processTitle: .subheadline
        case .process: .footnote
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        case .code: .footnote
        case .codeSmall: .caption
        case .codeCaption: .caption2
        case .hero: .largeTitle
        }
    }

    /// `headline` is the one role that bakes its weight; everything else takes it from the caller.
    var bakedWeight: Font.Weight? {
        self == .headline ? .semibold : nil
    }
}

/// SF Symbol sizes. Icons are not text roles.
enum GlyphSize: Hashable, Sendable {
    case small  // 13
    case regular  // 17
    case large  // 20
    case xlarge  // 28
    case hero  // 34

    var size: CGFloat {
        switch self {
        case .small: 13
        case .regular: 17
        case .large: 20
        case .xlarge: 28
        case .hero: 34
        }
    }
}

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
    static let serifName: String? = {
        ClaudeFontResources.register()
        if ClaudeFontResources.isAvailable(ClaudeFontResources.anthropicSerif) {
            return ClaudeFontResources.anthropicSerif
        }
        if ClaudeFontResources.isAvailable(ClaudeFontResources.newsreader) {
            return ClaudeFontResources.newsreader
        }
        return nil
    }()
    static let sansName: String? = {
        ClaudeFontResources.register()
        return ClaudeFontResources.isAvailable(ClaudeFontResources.anthropicSans)
            ? ClaudeFontResources.anthropicSans : nil
    }()
    static let monoName: String? = {
        ClaudeFontResources.register()
        return ClaudeFontResources.isAvailable(ClaudeFontResources.anthropicMono)
            ? ClaudeFontResources.anthropicMono : nil
    }()

    /// The serif face name the Markdown theme wants, resolved once.
    static let resolvedSerifName: String = serifName ?? ClaudeFontResources.newsreader

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

    private static func make(role: TextRole, weight: Font.Weight) -> Font {
        switch role.face {
        case .serif:
            if let serifName {
                return Font.custom(serifName, size: role.size, relativeTo: role.relativeTo)
                    .weight(weight)
            }
            return scaledSystem(size: role.size, relativeTo: role.relativeTo, design: .serif, weight: weight)
        case .sans:
            if let sansName {
                return Font.custom(sansName, size: role.size, relativeTo: role.relativeTo)
                    .weight(weight)
            }
            return scaledSystem(size: role.size, relativeTo: role.relativeTo, design: .default, weight: weight)
        case .mono:
            if let monoName {
                return Font.custom(monoName, size: role.size, relativeTo: role.relativeTo)
                    .weight(weight)
            }
            return scaledSystem(size: role.size, relativeTo: role.relativeTo, design: .monospaced, weight: weight)
        }
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
        weight: Font.Weight
    ) -> Font {
        let system = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        let descriptor = system.fontDescriptor.withDesign(design) ?? system.fontDescriptor
        let face = UIFont(descriptor: descriptor, size: size)
        return Font(UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: face))
    }

    /// The same face and size a role's `Font` draws with, as a `UIFont`, for the UIKit views that
    /// have to set a font themselves (the composer's text view). Scaled through `UIFontMetrics`
    /// for the role's text style, so `adjustsFontForContentSizeCategory` keeps working.
    static func uiFont(_ role: TextRole, weight: Font.Weight = .regular) -> UIFont {
        let resolvedWeight = role.bakedWeight ?? weight
        let base: UIFont
        switch role.face {
        case .sans:
            base = sansName.flatMap { UIFont(name: $0, size: role.size) }
                ?? UIFont.systemFont(ofSize: role.size, weight: resolvedWeight.uiWeight)
        case .serif:
            base = serifName.flatMap { UIFont(name: $0, size: role.size) }
                ?? UIFont.systemFont(ofSize: role.size, weight: resolvedWeight.uiWeight)
        case .mono:
            base = monoName.flatMap { UIFont(name: $0, size: role.size) }
                ?? UIFont.monospacedSystemFont(ofSize: role.size, weight: resolvedWeight.uiWeight)
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

/// Prose keeps its own sizes (`Conversation/Prose/`); this is the one cached builder it uses.
/// `relativeTo: .body` keeps the shifted Dynamic Type scaling prose with the rest of the app.
enum ProseFonts {
    static let serifName = Typography.resolvedSerifName

    private struct Key: Hashable {
        let face: TextRole.Face
        let size: CGFloat
        let relativeTo: Font.TextStyle
        let weight: Font.Weight
        let italic: Bool
    }

    private static let fonts = Mutex<[Key: Font]>([:])

    /// Real faces, not modifiers: the bundled serif has no bold or italic face, so `.weight(_:)`
    /// and `.italic()` on it draw Regular. `ProseFaceTable` picks the face name; this builds it.
    static func serif(
        size: CGFloat, relativeTo: Font.TextStyle = .body, weight: Font.Weight = .regular,
        italic: Bool = false
    ) -> Font {
        font(.serif, size: size, relativeTo: relativeTo, weight: weight, italic: italic)
    }

    static func sans(size: CGFloat, relativeTo: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        font(.sans, size: size, relativeTo: relativeTo, weight: weight)
    }

    static func mono(size: CGFloat, relativeTo: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        font(.mono, size: size, relativeTo: relativeTo, weight: weight)
    }

    private static func font(
        _ face: TextRole.Face, size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight,
        italic: Bool = false
    ) -> Font {
        let key = Key(face: face, size: size, relativeTo: style, weight: weight, italic: italic)
        return fonts.withLock { cache in
            if let hit = cache[key] { return hit }
            var name: String?
            switch face {
            case .serif: name = Typography.serifName
            case .sans: name = Typography.sansName
            case .mono: name = Typography.monoName
            }
            // The serif asks ProseFaceTable for the face that draws this weight and slant. A real
            // face gets no `.weight()`/`.italic()` (the file has no such face, which was the bug);
            // the Regular roman keeps exactly the modifiers it had before J1.
            var serifFace: ProseFaceTable.Face?
            if face == .serif {
                let resolved = ProseFaceTable.face(weight: weight.rank, italic: italic)
                name = resolved.postScriptName
                serifFace = resolved
            }
            let font: Font
            if let name {
                var built = Font.custom(name, size: size, relativeTo: style)
                if let serifFace {
                    if let visible = ProseFaceTable.visibleWeight(serifFace, requested: weight) {
                        built = built.weight(visible)
                    }
                    if ProseFaceTable.visibleItalic(serifFace, requested: italic) {
                        built = built.italic()
                    }
                } else {
                    built = built.weight(weight)
                }
                font = built
            } else {
                switch face {
                case .serif:
                    font = Typography.scaledSystem(size: size, relativeTo: style, design: .serif, weight: weight)
                case .sans:
                    font = Typography.scaledSystem(size: size, relativeTo: style, design: .default, weight: weight)
                case .mono:
                    font = Typography.scaledSystem(size: size, relativeTo: style, design: .monospaced, weight: weight)
                }
            }
            cache[key] = font
            return font
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
private struct CodeSizeStepKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    public var codeSizeStep: Int {
        get { self[CodeSizeStepKey.self] }
        set { self[CodeSizeStepKey.self] = newValue }
    }
}

extension View {
    /// Scale a code container by the Code size setting on top of the content Dynamic Type size.
    func codeTypeScale() -> some View {
        modifier(CodeTypeScale())
    }
}

private struct CodeTypeScale: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.codeSizeStep) private var codeSizeStep

    func body(content: Content) -> some View {
        content.dynamicTypeSize(dynamicTypeSize.shifted(by: codeSizeStep))
    }
}

/// The app-wide typography facade: prose and Markdown keep naming sizes (they are measured
/// against their own body size), everything else uses `Font.paseo(_:)`.
public struct ClaudeTypography: Sendable {
    public static let anthropicSans = ClaudeFontResources.anthropicSans
    public static let anthropicSerif = ClaudeFontResources.anthropicSerif
    public static let anthropicMono = ClaudeFontResources.anthropicMono
    public static let newsreader = ClaudeFontResources.newsreader

    public init() {}

    /// Assistant prose, greeting, sidebar title, headings.
    public func serif(
        _ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular,
        italic: Bool = false
    ) -> Font {
        ProseFonts.serif(size: size, relativeTo: style, weight: weight, italic: italic)
    }

    /// UI text, buttons, composer, sidebar rows.
    public func sans(
        _ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular
    ) -> Font {
        ProseFonts.sans(size: size, relativeTo: style, weight: weight)
    }

    /// Code, tool output, diffs.
    public func mono(
        _ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular
    ) -> Font {
        ProseFonts.mono(size: size, relativeTo: style, weight: weight)
    }

    /// The name the Markdown theme needs; Anthropic Serif with Newsreader as the fallback.
    public var resolvedSerifName: String { Typography.resolvedSerifName }
}
#endif
