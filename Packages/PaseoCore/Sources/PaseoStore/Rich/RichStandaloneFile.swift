import Foundation

// MARK: - RichStandaloneFile (G10 C10)

// NOTE: RemoteImagePipeline/G10: a path standing alone on its line becomes a file
// card; the same path inside a sentence stays inline (a chip today). The detector
// cannot tell the two apart without breaking its contract — it sees linkified text,
// where the standalone line is already an authored link — so the splice decides from
// the raw unit: exactly one `.localFileLink` block whose text *is* the path.

/// The standalone-vs-inline file-path rule, as pure data: detector blocks plus the
/// raw unit text. Tested on Linux.
public enum RichStandaloneFile {
    /// The file path when `blocks` is exactly one `.localFileLink` and the raw unit
    /// is verbatim that path (whitespace aside). Anything else — inline mentions,
    /// several paths, images — returns nil and keeps the existing rendering.
    public static func path(in blocks: [RichContentBlock], unitText: String) -> String? {
        guard blocks.count == 1, case .localFileLink(let path, _) = blocks[0],
            unitText.trimmingCharacters(in: .whitespacesAndNewlines) == path
        else { return nil }
        return path
    }
}
