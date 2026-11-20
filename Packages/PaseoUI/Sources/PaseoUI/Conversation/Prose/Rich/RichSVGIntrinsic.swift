#if canImport(UIKit)
import OSLog
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// The `<svg>` element's intrinsic aspect ratio: `viewBox` first (the drawing's real geometry),
/// then `width`/`height` attributes in px. Percentages are ignored — they say nothing about the
/// drawing itself. Used to reserve the card's height before the snapshot lands.
enum RichSVGIntrinsic {
    static func aspectRatio(of source: String) -> CGFloat? {
        guard let open = source.range(of: "<svg", options: .caseInsensitive),
            let tagEnd = source.range(of: ">", range: open.upperBound..<source.endIndex)
        else { return nil }
        let tag = source[open.upperBound..<tagEnd.lowerBound]

        if let viewBox = attribute("viewBox", in: tag) {
            let parts = viewBox.split { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n" }
                .compactMap { Double($0) }
            if parts.count == 4, parts[2] > 0, parts[3] > 0 {
                return CGFloat(parts[2] / parts[3])
            }
        }
        if let width = length(attribute("width", in: tag)),
            let height = length(attribute("height", in: tag)), height > 0
        {
            return width / height
        }
        return nil
    }

    /// `"400"` or `"400px"` → 400; `"100%"` → nil.
    private static func length(_ value: String?) -> CGFloat? {
        guard let value else { return nil }
        let digits = value.prefix { $0.isNumber || $0 == "." }
        guard digits.count == value.trimmingCharacters(in: .whitespaces).count
            || value.hasSuffix("px"),
            let number = Double(digits), number > 0
        else { return nil }
        return CGFloat(number)
    }

    private static func attribute(_ name: String, in tag: Substring) -> String? {
        // Attribute order is free and quoting may be single or double.
        var search = tag.startIndex..<tag.endIndex
        while let hit = tag.range(of: name, options: .caseInsensitive, range: search) {
            // The name must start an attribute, not sit inside one (`stroke-width`, a value).
            let startsAttribute = hit.lowerBound == tag.startIndex
                || tag[tag.index(before: hit.lowerBound)].isWhitespace
            guard startsAttribute else {
                search = hit.upperBound..<tag.endIndex
                continue
            }
            var cursor = hit.upperBound
            while cursor < tag.endIndex, tag[cursor] == " " { cursor = tag.index(after: cursor) }
            guard cursor < tag.endIndex, tag[cursor] == "=" else {
                search = hit.upperBound..<tag.endIndex
                continue
            }
            cursor = tag.index(after: cursor)
            while cursor < tag.endIndex, tag[cursor] == " " { cursor = tag.index(after: cursor) }
            guard cursor < tag.endIndex, tag[cursor] == "\"" || tag[cursor] == "'" else {
                return nil
            }
            let quote = tag[cursor]
            let valueStart = tag.index(after: cursor)
            guard let valueEnd = tag[valueStart...].firstIndex(of: quote) else { return nil }
            return String(tag[valueStart..<valueEnd])
        }
        return nil
    }
}
#endif
