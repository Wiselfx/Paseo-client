import Foundation
import PaseoProtocol

// MARK: - RichImageGrouping (G7 C2)

// NOTE: RemoteImagePipeline/G7: agents often post several screenshots in a row
// (before/after, three breakpoints). Today they stack into a tall column; adjacent
// image blocks separated only by blank lines become one grid card instead.

/// One image inside a gallery: a remote URL or a workspace path, with its alt text.
public struct RichImage: Sendable, Equatable, Hashable {
    public enum Source: Sendable, Equatable, Hashable {
        case remote(url: String)
        case local(path: String)
    }

    public var source: Source
    public var alt: String

    public init(source: Source, alt: String) {
        self.source = source
        self.alt = alt
    }

    /// The single-image blocks that may join a gallery, with their identity. SVG
    /// sources stay out: they keep their own vector card instead of a tile.
    public static func of(block: RichContentBlock) -> RichImage? {
        switch block {
        case .bareImageURL(let url, _):
            guard !url.lowercased().contains(".svg") else { return nil }
            return RichImage(source: .remote(url: url), alt: "")
        case .localImage(let path, let alt, _):
            guard (path as NSString).pathExtension.lowercased() != "svg" else { return nil }
            return RichImage(source: .local(path: path), alt: alt)
        default:
            return nil
        }
    }
}

/// The pure grouping rule, tested on Linux. The splice loop owns the iteration; these
/// decide merges.
public enum RichImageGrouping {
    /// Whether `next` extends a run that ended at `previous`: both sides are single
    /// images and the source text strictly between them is blank (whitespace only).
    /// A single newline qualifies — consecutive image lines are the common case — while
    /// any prose, heading or list markup between them breaks the run.
    public static func continuesRun(
        next: RichContentBlock, after previous: RichContentBlock, separatorIsBlank: Bool
    ) -> Bool {
        guard separatorIsBlank else { return false }
        guard RichImage.of(block: previous) != nil, RichImage.of(block: next) != nil else {
            return false
        }
        return true
    }

    /// Folds the images into one gallery block spanning the run.
    public static func group(images: [RichImage], range: Range<String.Index>) -> RichContentBlock {
        .imageGroup(images: images, range: range)
    }

    // MARK: - Images in one paragraph (J2 §1)

    /// NOTE: J2: an agent writes four screenshots on one line —
    /// `![one](/a.png) ![two](/b.png) ![remote](https://…)` — and markdown keeps them in
    /// one paragraph. Those are four `.image` inline children, not four units, so the
    /// run-merging above never saw them and each fell back to `"▧ alt"` text.
    ///
    /// The images when the unit's text, trimmed, is nothing but markdown images separated
    /// by whitespace (spaces, line breaks). Any other character — prose, a link, a code
    /// span, a list marker — returns nil and the unit renders as markdown. `home` expands
    /// `~/` and relative sources for the viewer (nil keeps them as written).
    public static func imagesOnly(unit: String, home: String? = nil) -> [RichImage]? {
        var images: [RichImage] = []
        var i = unit.startIndex
        while true {
            while i < unit.endIndex, unit[i].isWhitespace { i = unit.index(after: i) }
            guard i < unit.endIndex else { break }
            guard let image = parseImage(unit, at: &i, home: home) else { return nil }
            images.append(image)
        }
        return images.isEmpty ? nil : images
    }

    /// One `![alt](src "title")` at `i` (no whitespace allowed between the three parts, as
    /// in CommonMark). Advances `i` past it, or returns nil without moving past `i`.
    private static func parseImage(
        _ unit: String, at i: inout String.Index, home: String?
    ) -> RichImage? {
        var cursor = i
        func next(_ index: String.Index) -> String.Index { unit.index(after: index) }
        guard cursor < unit.endIndex, unit[cursor] == "!", next(cursor) < unit.endIndex,
            unit[next(cursor)] == "["
        else { return nil }
        let altStart = next(next(cursor))
        var j = altStart
        var altEnd: String.Index?
        while j < unit.endIndex {
            if unit[j] == "]" { altEnd = j; break }
            if unit[j] == "[" || unit[j] == "\n" { break }
            j = next(j)
        }
        guard let altEnd, next(altEnd) < unit.endIndex, unit[next(altEnd)] == "(" else {
            return nil
        }
        var k = next(next(altEnd))
        var close: String.Index?
        while k < unit.endIndex {
            if unit[k] == ")" { close = k; break }
            if unit[k] == "(" || unit[k] == "\n" { break }
            k = next(k)
        }
        guard let close else { return nil }
        let inner = String(unit[unit.index(after: next(altEnd))..<close])
            .trimmingCharacters(in: .whitespaces)
        // Destination, then optional "title" / 'title' / (title).
        let destination = inner.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        let alt = String(unit[altStart..<altEnd])
        cursor = unit.index(after: close)
        guard let destination else { return nil }
        let target = destination.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        let source: RichImage.Source
        switch RichLocalSource.image(target, home: home) {
        case .remoteImage(let url): source = .remote(url: url)
        case .file(let path): source = .local(path: path)
        case nil: return nil
        }
        i = cursor
        return RichImage(source: source, alt: alt)
    }
}
