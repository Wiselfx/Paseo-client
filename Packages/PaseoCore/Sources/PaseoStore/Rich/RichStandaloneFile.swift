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

    // MARK: - Lines that are only links to files (J2 §2)

    /// NOTE: J2: markdown joins soft-broken lines into one paragraph, so an agent that
    /// wrote four lines — `[clip.mp4](/media/clip.mp4)`, `[tone.m4a](…)`, `[doc.pdf](…)`,
    /// `[stats.py](…)` — produced one wrapped run of blue links instead of a player, an
    /// audio row and file cards. `path(in:unitText:)` above only recognises a unit that
    /// *is* a bare path; authored links were never considered.
    ///
    /// The paths in order when every non-blank line is either a bare local path or a
    /// single authored link to a local path; nil otherwise (prose, two links on a line,
    /// a remote URL, an anchor, `mailto:`). One line counts too: `[clip.mp4](/m/clip.mp4)`
    /// becomes a card exactly like the bare path does. `home` expands `~/` and relative
    /// paths; nil returns them as written.
    public static func linkLines(unit: String, home: String? = nil) -> [String]? {
        var paths: [String] = []
        var sawLine = false
        for line in unit.split(omittingEmptySubsequences: false, whereSeparator: \Character.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            sawLine = true
            guard let path = linePath(trimmed, home: home) else { return nil }
            paths.append(path)
        }
        guard sawLine else { return nil }
        return paths
    }

    /// Whether the unit is a list (its first non-blank line starts with `-`, `*`, `+` or
    /// `1.` / `1)`): the splice renders list units whole instead of cutting a player out
    /// of them (J2 §4). Up to three leading spaces are allowed, as in CommonMark.
    public static func isListUnit(_ unit: String) -> Bool {
        for line in unit.split(omittingEmptySubsequences: false, whereSeparator: \Character.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let indent = line.prefix(while: { $0 == " " }).count
            guard indent <= 3 else { return false }
            return isListItemLine(trimmed)
        }
        return false
    }

    private static func isListItemLine(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        if first == "-" || first == "*" || first == "+" {
            let rest = line.dropFirst()
            return rest.isEmpty || rest.first?.isWhitespace == true
        }
        var digits = 0
        var index = line.startIndex
        while index < line.endIndex, line[index].isASCII, line[index].isNumber, digits < 9 {
            digits += 1
            index = line.index(after: index)
        }
        guard digits > 0, index < line.endIndex, line[index] == "." || line[index] == ")" else {
            return false
        }
        let rest = line[line.index(after: index)...]
        return rest.isEmpty || rest.first?.isWhitespace == true
    }

    /// One line as a local path: a bare path, or exactly one authored link to one.
    /// A remote destination is deliberately not a file: a link to a site is a web link.
    private static func linePath(_ line: String, home: String?) -> String? {
        if let link = soleLink(in: line) {
            guard !link.contains("://"), !link.hasPrefix("mailto:"),
                let path = RichLocalSource.filePath(link, home: home)
            else { return nil }
            return path
        }
        guard !line.contains("["), !line.contains("]"), !line.contains("`"),
            !line.contains(where: \.isWhitespace)
        else { return nil }
        return RichLocalSource.filePath(line, home: home)
    }

    /// The destination when `line` is exactly `[text](destination)`, else nil.
    private static func soleLink(in line: String) -> String? {
        guard line.hasPrefix("["), let textEnd = line.firstIndex(of: "]") else { return nil }
        let afterText = line.index(after: textEnd)
        guard afterText < line.endIndex, line[afterText] == "(", line.hasSuffix(")") else {
            return nil
        }
        let inner = String(line[line.index(after: afterText)..<line.index(before: line.endIndex)])
            .trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty, !inner.contains("("), !inner.contains(")") else { return nil }
        let destination = inner.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        guard let destination else { return nil }
        return destination.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
    }
}
