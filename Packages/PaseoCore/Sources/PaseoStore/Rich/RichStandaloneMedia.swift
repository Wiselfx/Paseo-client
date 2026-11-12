import Foundation

// MARK: - RichStandaloneMedia (G11 C3, C4)

// NOTE: RemoteImagePipeline/G11: like standalone file lines (G10), a standalone media
// path or URL becomes a player card — decided from the raw unit, before linkification
// wraps it into an authored link the detector would then ignore.

/// The playable kinds. Unknown extensions (and `.webm`, which AVFoundation cannot
/// play) are not media: they stay file or link cards.
public enum MediaFileKind: Sendable, Equatable, Hashable {
    case video
    case audio
}

/// Standalone media: a bare path or bare URL alone on its line with a playable
/// extension. Inline mentions keep their existing rendering.
public enum RichStandaloneMedia {
    /// The playable extensions. `.webm` is deliberately absent: AVFoundation cannot
    /// play it, so it stays a file card (C3).
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    public static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "caf", "aiff"]

    public enum Ref: Sendable, Equatable {
        /// A bare absolute or `~/` path.
        case local(path: String, kind: MediaFileKind)
        /// A bare remote URL.
        case remote(url: String, kind: MediaFileKind)
    }

    /// The media ref when `unitText` is verbatim a single bare path or bare URL with a
    /// playable extension — and, for paths, when the detector agrees it is a plain
    /// local file link (not an image). `blocks` are the detector's output for the raw
    /// unit, mirroring the G10 file check.
    public static func match(blocks: [RichContentBlock], unitText: String) -> Ref? {
        let trimmed = unitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A bare remote URL alone on the line.
        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let kind = kindForURL(url)
        {
            return .remote(url: trimmed, kind: kind)
        }
        // A bare local path alone on the line.
        guard blocks.count == 1,
            case .localFileLink(let path, _) = blocks[0],
            path == trimmed,
            let kind = kindForPath(path)
        else { return nil }
        return .local(path: path, kind: kind)
    }

    /// The playable kind for a path, or nil (images, documents, `.webm`, unknowns).
    public static func kindForPath(_ path: String) -> MediaFileKind? {
        let ext = (path as NSString).pathExtension.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        return nil
    }

    /// The playable kind for a remote URL, or nil. Query and fragment are ignored.
    public static func kindForURL(_ url: URL) -> MediaFileKind? {
        kindForPath(url.path)
    }
}
