#if canImport(UIKit)
import Foundation
import SwiftUI
import Synchronization

/// The single source of truth for "which PostScript face draws this weight/italic" (J1 §1).
///
/// Each bundled family is one variable file per slant, and a weight is a named instance inside it
/// (read from the files with `fc-scan`, never guessed). SwiftUI's `.weight(_:)` and `.italic()` do
/// not reliably select a variable instance — the original bug was the single-weight Anthropic
/// serif drawing Regular for both — so the app asks for the instance by name instead.
///
/// The plain Roman of each family is never taken from the weight tables: regular body prose keeps
/// exactly the face `Typography` resolved the family to, so no paragraph changes family or metrics.
///
/// Pure and UI-free: it decides *names*, `ProseFonts` builds fonts from them.
enum ProseFaceTable {
    /// One family's file for one slant, and the real faces it declares.
    enum FaceFile: CaseIterable, Sendable {
        case sansRoman
        case sansItalic
        case serifRoman
        case serifItalic
        case monoRoman
        case monoItalic

        var isItalic: Bool {
            switch self {
            case .sansItalic, .serifItalic, .monoItalic: true
            case .sansRoman, .serifRoman, .monoRoman: false
            }
        }

        /// Ascending weight. Only the weights the app asks for are listed, so a roman table starts
        /// at Medium (Regular is the file's own default face, `baseFace`) and an italic table
        /// starts at Regular (where the italic file's default instance sits). UltraLight, Thin and
        /// Light are never requested; anything heavier than SemiBold takes SemiBold.
        var declaredFaces: [(weight: Font.Weight, name: String)] {
            switch self {
            case .sansRoman:
                [
                    (.medium, "InterVariable-Medium"),
                    (.semibold, "InterVariable-SemiBold"),
                ]
            case .sansItalic:
                [
                    (.regular, ClaudeFontResources.interItalic),
                    (.medium, "InterVariableItalic-Medium"),
                    (.semibold, "InterVariableItalic-SemiBold"),
                ]
            case .serifRoman:
                [
                    (.medium, "NewsreaderRoman-Medium"),
                    (.semibold, "NewsreaderRoman-SemiBold"),
                    (.bold, "NewsreaderRoman-Bold"),
                    (.heavy, "NewsreaderRoman-ExtraBold"),
                ]
            case .serifItalic:
                [
                    (.regular, ClaudeFontResources.newsreaderItalic),
                    (.medium, "NewsreaderItalic-Medium"),
                    (.semibold, "NewsreaderItalic-SemiBold"),
                    (.bold, "NewsreaderItalic-Bold"),
                    (.heavy, "NewsreaderItalic-ExtraBold"),
                ]
            case .monoRoman:
                [
                    (.medium, "JetBrainsMono-Medium"),
                    (.semibold, "JetBrainsMono-SemiBold"),
                ]
            case .monoItalic:
                [
                    (.regular, ClaudeFontResources.jetBrainsMonoItalic),
                    (.medium, "JetBrainsMonoItalic-MediumItalic"),
                    (.semibold, "JetBrainsMonoItalic-SemiBoldItalic"),
                ]
            }
        }

        /// The file's own default PostScript name. `Typography` resolves the family to it, and
        /// `ClaudeFontResources.isAvailable` asks about it to learn whether the file is registered
        /// at all: a bundled-but-unregistered file is not usable.
        var baseFace: String {
            switch self {
            case .sansRoman: ClaudeFontResources.inter
            case .sansItalic: ClaudeFontResources.interItalic
            case .serifRoman: ClaudeFontResources.newsreader
            case .serifItalic: ClaudeFontResources.newsreaderItalic
            case .monoRoman: ClaudeFontResources.jetBrainsMono
            case .monoItalic: ClaudeFontResources.jetBrainsMonoItalic
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

        /// The unstyled Regular roman: every fallback returns exactly this.
        var isRegularRoman: Bool { !file.isItalic && weight == .regular && !isItalic }
    }

    // MARK: (family, weight, italic) → face

    /// The face for `family` asked at `weight` with or without a slant.
    ///
    /// - `weight <= .regular` with no slant returns the regular roman before the table is read:
    ///   the body paragraph keeps the face it has always had.
    /// - Anything else returns a real face from the bundled files. A missing file, or a named
    ///   instance CoreText does not expose, falls back to the regular roman, which then keeps the
    ///   requested weight as a modifier exactly as it did before.
    static func face(_ family: TextRole.Face, weight: Font.Weight, italic: Bool) -> Face {
        let roman = file(family, italic: false)
        let regularRoman = Face(
            postScriptName: Typography.baseName(family) ?? roman.baseFace, file: roman,
            weight: .regular, isItalic: false)
        if !italic, weight.rank <= Font.Weight.regular.rank { return regularRoman }
        let target = file(family, italic: italic)
        guard let name = declaredName(in: target, weight: weight), fileShips(target),
            ClaudeFontResources.isAvailable(name)
        else {
            return regularRoman
        }
        return Face(
            postScriptName: name, file: target, weight: declaredWeight(name), isItalic: italic)
    }

    /// The file that declares `family`'s faces for one slant.
    static func file(_ family: TextRole.Face, italic: Bool) -> FaceFile {
        switch (family, italic) {
        case (.sans, false): .sansRoman
        case (.sans, true): .sansItalic
        case (.serif, false): .serifRoman
        case (.serif, true): .serifItalic
        case (.mono, false): .monoRoman
        case (.mono, true): .monoItalic
        }
    }

    /// The lightest declared face in `file` at or above `weight`'s step, else the heaviest declared.
    /// That is why `.semibold` is 600 and not 700. Pure.
    static func declaredName(in file: FaceFile, weight: Font.Weight) -> String? {
        let faces = file.declaredFaces
        return (faces.first { $0.weight.rank >= weight.rank } ?? faces.last)?.name
    }

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
    /// regular roman (where the modifier is a no-op on a static file and a variable axis elsewhere).
    static func visibleWeight(_ face: Face, requested: Font.Weight) -> Font.Weight? {
        face.isRegularRoman ? requested : nil
    }

    /// The slant to put on `face` with `.italic()`: none for a real italic face, the request
    /// otherwise (a no-op on a static roman, a variable axis elsewhere).
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
            let present = ClaudeFontResources.isAvailable(file.baseFace)
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
