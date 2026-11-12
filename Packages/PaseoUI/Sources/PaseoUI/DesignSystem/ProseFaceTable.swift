#if canImport(UIKit)
import Foundation
import SwiftUI
import Synchronization

/// The single source of truth for "which PostScript face draws this weight/italic" (J1 §1).
///
/// The bundled Anthropic serif (`AnthropicSerifWebText.ttf`) is one static Regular face, so
/// `Font.custom(anthropicSerif, size:)` + `.weight(_:)` / `.italic()` are no-ops: SwiftUI has no
/// heavier or slanted face to switch to. The Newsreader files do carry real faces (read from the
/// bundled files with `fc-scan`, never guessed), so prose asks for a face name instead.
///
/// Pure and UI-free: it decides *names*, `ProseFonts` builds fonts from them.
enum ProseFaceTable {
    /// The bundled serif files, and the faces declared in each.
    enum FaceFile: CaseIterable, Sendable {
        case roman
        case italic

        var resourceName: String {
            switch self {
            case .roman: ClaudeFontResources.newsreaderRomanFile
            case .italic: ClaudeFontResources.newsreaderItalicFile
            }
        }

        /// Ascending weight, so `declaredName` can walk it in order.
        var declaredFaces: [(weight: Font.Weight, name: String)] {
            switch self {
            case .roman:
                [
                    (.extraLight, "NewsreaderRoman-ExtraLight"),
                    (.thin, "NewsreaderRoman-ExtraLight"),
                    (.light, "NewsreaderRoman-Light"),
                    (.regular, "Newsreader16pt-Regular"),
                    (.medium, "NewsreaderRoman-Medium"),
                    (.semibold, "NewsreaderRoman-SemiBold"),
                    (.bold, "NewsreaderRoman-Bold"),
                    (.heavy, "NewsreaderRoman-ExtraBold"),
                    (.black, "NewsreaderRoman-ExtraBold"),
                ]
            case .italic:
                [
                    (.extraLight, "NewsreaderItalic-ExtraLight"),
                    (.thin, "NewsreaderItalic-ExtraLight"),
                    (.light, "NewsreaderItalic-Light"),
                    (.regular, "Newsreader16pt-Italic"),
                    (.medium, "NewsreaderItalic-Medium"),
                    (.semibold, "NewsreaderItalic-SemiBold"),
                    (.bold, "NewsreaderItalic-Bold"),
                    (.heavy, "NewsreaderItalic-ExtraBold"),
                    (.black, "NewsreaderItalic-ExtraBold"),
                ]
            }
        }
    }

    /// One rung of the table: the PostScript name, the file that declares it, and the weight and
    /// slant it already draws.
    struct Face: Hashable, Sendable {
        let postScriptName: String
        let file: FaceFile
        let weight: Font.Weight
        let isItalic: Bool
    }

    // MARK: (weight, italic) → face

    /// The face for prose asked at `weight` with or without a slant. Every name is one of the real
    /// faces in the bundled files (`fc-scan`); `visibleWeight`/`visibleItalic` then decide what the
    /// caller may add on top. A missing file falls back to the Regular roman, which is exactly what
    /// prose drew before J1.
    static func face(weight: Int, italic: Bool) -> Face {
        if italic {
            guard let name = declaredName(in: .italic, weight: weight), fileShips(.italic) else {
                return regularRoman
            }
            return Face(
                postScriptName: name, file: .italic, weight: declaredWeight(name), isItalic: true)
        }
        guard let name = declaredName(in: .roman, weight: weight), fileShips(.roman) else {
            return regularRoman
        }
        return Face(
            postScriptName: name, file: .roman, weight: declaredWeight(name), isItalic: false)
    }

    /// The face prose has drawn since before J1: the resolved serif, Regular roman, no real weight.
    private static let regularRoman = Face(
        postScriptName: Typography.resolvedSerifName, file: .roman, weight: .regular, isItalic: false)

    /// The weight a declared name draws, by looking it up in its own file's table.
    private static func declaredWeight(_ name: String) -> Font.Weight {
        for file in FaceFile.allCases {
            if let declared = file.declaredFaces.first(where: { $0.name == name }) {
                return declared.weight
            }
        }
        return .regular
    }

    /// The weight to put on `face` with `.weight(_:)`: none for a real face, the request for the
    /// Regular roman (where the modifier is a no-op, as it always was).
    static func visibleWeight(_ face: Face, requested: Font.Weight) -> Font.Weight? {
        face.weight == .regular && !face.isItalic && face.file == .roman ? requested : nil
    }

    /// The slant to put on `face` with `.italic()`: none for a real italic face, the request
    /// otherwise (a no-op on the roman, as it always was).
    static func visibleItalic(_ face: Face, requested: Bool) -> Bool {
        requested && !face.isItalic
    }

    // MARK: Availability, asked once per file

    private static let ships: Mutex<[FaceFile: Bool]> = Mutex([:])

    /// Whether the file that declares these faces is registered in this process. Resolved once:
    /// the answer decides which faces are ever asked for, and the check walks CoreText.
    static func fileShips(_ file: FaceFile) -> Bool {
        ships.withLock { cache in
            if let hit = cache[file] { return hit }
            let present =
                file.declaredFaces.contains { ClaudeFontResources.isAvailable($0.name) }
                || Bundle.module.url(forResource: file.resourceName, withExtension: "ttf") != nil
            cache[file] = present
            return present
        }
    }
}

extension Font.Weight {
    /// The weight's step on the nine-step ladder. SwiftUI exposes no ordering of its weights, so
    /// the face table needs one; this is the ladder `Font.Weight` documents.
    var rank: Int {
        switch self {
        case .ultraLight: 0
        case .thin: 1
        case .light: 2
        case .regular: 3
        case .medium: 4
        case .semibold: 5
        case .bold: 6
        case .heavy: 7
        case .black: 8
        default: 3
        }
    }
}
#endif
