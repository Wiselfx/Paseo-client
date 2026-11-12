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
/// The Regular roman is never taken from the table: regular body prose keeps exactly the face it
/// drew before J1 (`Typography.resolvedSerifName`), so no paragraph changes family or metrics.
///
/// Pure and UI-free: it decides *names*, `ProseFonts` builds fonts from them.
enum ProseFaceTable {
    /// The bundled serif files, and the real faces declared in each.
    enum FaceFile: CaseIterable, Sendable {
        case roman
        case italic

        /// Ascending weight. Only the weight-bearing faces are listed: UltraLight/Thin/Light and
        /// Regular are not real steps prose asks for — anything at or below Regular takes the
        /// regular-roman path, and an italic below Medium still lands on the Regular italic.
        var declaredFaces: [(weight: Font.Weight, name: String)] {
            switch self {
            case .roman:
                [
                    (.medium, "NewsreaderRoman-Medium"),
                    (.semibold, "NewsreaderRoman-SemiBold"),
                    (.bold, "NewsreaderRoman-Bold"),
                    (.heavy, "NewsreaderRoman-ExtraBold"),
                ]
            case .italic:
                [
                    (.regular, "Newsreader16pt-Italic"),
                    (.medium, "NewsreaderItalic-Medium"),
                    (.semibold, "NewsreaderItalic-SemiBold"),
                    (.bold, "NewsreaderItalic-Bold"),
                    (.heavy, "NewsreaderItalic-ExtraBold"),
                ]
            }
        }

        /// One face of this file, enough for `ClaudeFontResources.isAvailable` to say whether the
        /// file is registered at all. A bundled-but-unregistered file is not usable.
        var probeFace: String { declaredFaces[0].name }
    }

    /// One rung of the table: the PostScript name, the file that declares it, and the weight and
    /// slant it already draws.
    struct Face: Hashable, Sendable {
        let postScriptName: String
        let file: FaceFile
        let weight: Font.Weight
        let isItalic: Bool

        /// The unstyled Regular roman: every fallback returns exactly this.
        var isRegularRoman: Bool { file == .roman && weight == .regular && !isItalic }
    }

    // MARK: (weight, italic) → face

    /// The face for prose asked at `weight` with or without a slant.
    ///
    /// - `weight <= .regular` with no slant returns `regularRoman` before the table is read: the
    ///   body paragraph keeps the face it has always had.
    /// - Anything else returns a real Newsreader face from the bundled files; a missing file falls
    ///   back to the regular roman, which is what prose drew before J1.
    static func face(weight: Font.Weight, italic: Bool) -> Face {
        if !italic, weight.rank <= Font.Weight.regular.rank { return regularRoman }
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

    /// The lightest declared face in `file` at or above `weight`'s step, else the heaviest declared.
    /// That is why `.semibold` is 600 and not 700. Pure.
    static func declaredName(in file: FaceFile, weight: Font.Weight) -> String? {
        let faces = file.declaredFaces
        return (faces.first { $0.weight.rank >= weight.rank } ?? faces.last)?.name
    }

    /// The face prose drew before J1: the resolved serif, Regular roman, no real weight.
    private static let regularRoman = Face(
        postScriptName: Typography.resolvedSerifName, file: .roman, weight: .regular, isItalic: false)

    /// The weight a declared name draws, looked up in its own file's table.
    private static func declaredWeight(_ name: String) -> Font.Weight {
        for file in FaceFile.allCases {
            if let declared = file.declaredFaces.first(where: { $0.name == name }) {
                return declared.weight
            }
        }
        return .regular
    }

    /// The weight to put on `face` with `.weight(_:)`: none for a real face, the request for the
    /// regular roman (where the modifier is a no-op, exactly as before J1).
    static func visibleWeight(_ face: Face, requested: Font.Weight) -> Font.Weight? {
        face.isRegularRoman ? requested : nil
    }

    /// The slant to put on `face` with `.italic()`: none for a real italic face, the request
    /// otherwise (a no-op on the roman, exactly as before J1).
    static func visibleItalic(_ face: Face, requested: Bool) -> Bool {
        requested && !face.isItalic
    }

    // MARK: Availability, asked once per file

    private static let ships = Mutex<[FaceFile: Bool]>([:])

    /// Whether the file that declares these faces is registered in this process, asked once per
    /// file: the answer decides which faces are ever requested. Registration, not presence in the
    /// bundle, is the test — CoreText substitutes silently for a file it never registered.
    static func fileShips(_ file: FaceFile) -> Bool {
        ships.withLock { cache in
            if let hit = cache[file] { return hit }
            let present = ClaudeFontResources.isAvailable(file.probeFace)
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
