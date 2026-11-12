import Foundation

// MARK: - RichLocalSource (J2)

// NOTE: J2: images and file links authored by an agent name their target explicitly —
// `![shot](/abs/media/one.png)`, `[clip.mp4](/abs/media/clip.mp4)` — instead of relying
// on the bare-path scanners. The authored destination may be absolute, `~/`, `./` or a
// relative path with an extension, which no existing helper accepted (they all wanted an
// absolute or `~/` path). This is the one place that answers "is this destination a local
// file, and is it an image or playable media".

/// Classification of an authored link destination that points at a local file.
public enum RichLocalSource: Sendable, Equatable, Hashable {
    /// `~/` or `./` expanded (the UI's file viewer resolves `~` and relative paths the
    /// same way it does for a bare path).
    case file(path: String)
    /// An `http(s)` / `data:` image source that reaches the app without `//`.
    case remoteImage(url: String)

    /// A destination written without a scheme but with a dotted first label
    /// (`one.png`, `./two.png`) is a file, never a host — `bareHosts` (`example.com`)
    /// stay remote.
    static let bareHosts: Set<String> = [
        "example.com", "example.org", "example.net", "localhost",
    ]

    /// The source an image may load: a local file, or an absolute remote image URL.
    /// `data:`/`blob:` sources stay out — the parser drops the payload's spaces, so they
    /// can never round-trip (the prose image path never supported them either).
    public static func image(_ raw: String, home: String?) -> RichLocalSource? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if RichContentDetector.isRemoteImageURL(trimmed) {
            return .remoteImage(url: trimmed)
        }
        guard let path = filePath(trimmed, home: home) else { return nil }
        return .file(path: path)
    }

    /// The file a link opens: a local path with an extension, or a scheme-less web URL,
    /// which becomes `https://` (markdown treats `[a](example.com/a)` as a relative
    /// link, but nobody writing prose means the local file `example.com/a`). Remote
    /// links come back as the URL itself — the same visible target, still an external
    /// open.
    public static func link(_ raw: String, home: String?) -> RichLocalSource? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        {
            return .file(path: trimmed)
        }
        // A scheme-less web URL first: `example.com` *is* a path (extension `com`) to the
        // file rule, so the host rule has to answer before it.
        if isSchemeLessWebURL(trimmed) { return .file(path: "https://" + trimmed) }
        if let path = filePath(trimmed, home: home) { return .file(path: path) }
        return nil
    }

    /// The expanded path when `raw` names a local file: absolute, `~/`, `./` or `../`,
    /// or a relative path whose last component carries an extension. Anything with a
    /// scheme (`http(s)`, `mailto:`, `paseo-file:`), a `#` fragment or a `?` query is
    /// not a path.
    public static func filePath(_ raw: String, home: String?) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("#"), !trimmed.contains("?") else { return nil }
        if trimmed.contains("://") || hasScheme(trimmed) { return nil }
        if trimmed.hasPrefix("/") { return trimmed }
        if trimmed.hasPrefix("~/") { return expandHome(trimmed, home: home) }
        if trimmed.hasPrefix("./") || trimmed.hasPrefix("../") {
            return joinedWithHome(trimmed, home: home)
        }
        // A relative path: only with an extension, so prose words never become files.
        guard !trimmed.hasSuffix("/"), (trimmed as NSString).pathExtension.isEmpty == false else {
            return nil
        }
        return joinedWithHome(trimmed, home: home)
    }

    // MARK: - Helpers

    /// `RFC 3986` scheme: a letter followed by letters, digits, `+`, `-` or `.`, then `:`.
    private static func hasScheme(_ value: String) -> Bool {
        guard let colon = value.firstIndex(of: ":") else { return false }
        let scheme = value[value.startIndex..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.dropFirst().allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".")
        }
    }

    /// A bare host with a path or port: `firstLabel.tld/…`, `firstLabel.tld:8080`.
    /// A `bareHosts` label qualifies on its own; anything else needs a slash or port,
    /// so a lone `README.md` stays a file.
    private static func isSchemeLessWebURL(_ value: String) -> Bool {
        let firstSegment = value.prefix(while: { $0 != "/" && $0 != ":" })
        guard let dot = firstSegment.firstIndex(of: ".") else { return false }
        let host = firstSegment[firstSegment.startIndex..<dot]
        guard !host.isEmpty else { return false }
        let label = firstSegment[dot...].dropFirst()
        guard label.first?.isLetter == true else { return false }
        if bareHosts.contains(firstSegment.lowercased()) { return true }
        // A port or a path after the host: `example.com:8080`, `example.com/a/b`.
        return firstSegment != value
    }
    /// `~` is the agent's home; without one the path keeps its `~` (the viewer tries the
    /// same expansion of the raw path).
    private static func expandHome(_ path: String, home: String?) -> String {
        guard let home, !home.isEmpty else { return path }
        let trimmedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        return trimmedHome + path.dropFirst()
    }

    /// A relative path (`./a.png`, `../shots/a.png`, `docs/a.png`) joined onto the agent's
    /// home. Without one it keeps its relative form: the viewer resolves it against the
    /// workspace, like a bare path.
    private static func joinedWithHome(_ path: String, home: String?) -> String {
        guard let home, !home.isEmpty else { return path }
        let trimmedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        let stripped = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        return trimmedHome + "/" + stripped
    }
}
