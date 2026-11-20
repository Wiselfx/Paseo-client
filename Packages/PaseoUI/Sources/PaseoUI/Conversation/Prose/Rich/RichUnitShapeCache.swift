#if canImport(UIKit)
import Foundation
import PaseoStore

/// The unit-shape checks J2 added (images-only, file-link lines, list unit) scan the whole
/// unit; `richPieces` runs from view bodies, so they are memoized per (unit, home) like
/// `RichContentCache` — never re-scanned per render (lead fix, mission-critical §1).
enum RichUnitShapeCache {
    struct Shape {
        let images: [RichImage]?
        let filePaths: [String]?
        let isList: Bool
    }

    private struct Key: Hashable {
        let unit: String
        let home: String?
    }

    private static let table = ProseCache<Key, Shape>(
        budget: 4 * 1024 * 1024,
        countLimit: 512,
        cost: { key, _ in key.unit.utf8.count })

    static func shape(_ unit: String, home: String?) -> Shape {
        let key = Key(unit: unit, home: home)
        if let cached = table.value(for: key) { return cached }
        let shape = Shape(
            images: RichImageGrouping.imagesOnly(unit: unit, home: home),
            filePaths: RichStandaloneFile.linkLines(unit: unit, home: home),
            isList: RichStandaloneFile.isListUnit(unit))
        table.setValue(shape, for: key)
        return shape
    }
}
#endif
