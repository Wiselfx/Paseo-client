#if canImport(UIKit)
import SwiftUI
import Synchronization
import UIKit

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

    /// Real faces, not modifiers: each bundled family declares a named instance per weight and
    /// slant, and `.weight(_:)`/`.italic()` do not reliably select one. `ProseFaceTable` picks the
    /// face name; this builds it.
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

    /// The one place a family, size, weight and slant become a `Font`, cached by all four.
    static func font(
        _ face: TextRole.Face, size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight,
        italic: Bool = false
    ) -> Font {
        let key = Key(face: face, size: size, relativeTo: style, weight: weight, italic: italic)
        return fonts.withLock { cache in
            if let hit = cache[key] { return hit }
            let font: Font
            if Typography.baseName(face) != nil {
                // A real face gets no `.weight()`/`.italic()`: the file declares the instance, and
                // the modifier was the bug. A named instance CoreText does not expose falls back
                // to the family's regular roman, which keeps the modifiers it had before.
                let resolved = ProseFaceTable.face(face, weight: weight, italic: italic)
                var built = Font.custom(resolved.postScriptName, size: size, relativeTo: style)
                if let visible = ProseFaceTable.visibleWeight(resolved, requested: weight) {
                    built = built.weight(visible)
                }
                if ProseFaceTable.visibleItalic(resolved, requested: italic) {
                    built = built.italic()
                }
                font = built
            } else {
                switch face {
                case .serif:
                    font = Typography.scaledSystem(size: size, relativeTo: style, design: .serif, weight: weight, italic: italic)
                case .sans:
                    font = Typography.scaledSystem(size: size, relativeTo: style, design: .default, weight: weight, italic: italic)
                case .mono:
                    font = Typography.scaledSystem(size: size, relativeTo: style, design: .monospaced, weight: weight, italic: italic)
                }
            }
            cache[key] = font
            return font
        }
    }
}
#endif
