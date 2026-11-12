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
    static func of(block: RichContentBlock) -> RichImage? {
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
}
