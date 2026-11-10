import Foundation

/// What the model says it is doing, read off the tail of the newest reasoning block
/// (`docs/research/08-dsh-live-observation.md` §3.1 — the precise status line). This is a
/// deliberate simplification of the reference implementation (`shared/activity-phrase.ts`):
///
/// - Sentence ends are found by scanning for terminal punctuation instead of `Intl.Segmenter`,
///   so an abbreviation ("e.g.") or a dotted name can split a sentence early. A wrong split only
///   ever produces or misses a candidate clause; it never crashes.
/// - Quotations are blanked for the scan so a clause is never read out of one, as in the source.
/// - English only; anything else, or no clause in the shape (auxiliary + ≤ 2 qualifiers +
///   an `-ing` participle), hands the line nothing and the caller falls back to "Thinking…".
enum ClaudeReasoningClause {
    /// How much of the reasoning's tail one scan reads, in characters.
    private static let tailChars = 800

    private static let sentenceMarks = CharacterSet(charactersIn: ".!?…。！？")
    private static let clauseEnds = CharacterSet(charactersIn: ",;:—–)，；：）")
    private static let closers = Set("\"'”’»)]}）】》")
    private static let qualifiers: Set<String> = [
        "not", "now", "currently", "still", "just", "already", "again", "simply", "only", "also", "really",
    ]
    private static let nominalIng: Set<String> = [
        "nothing", "anything", "everything", "something", "thing", "morning", "evening",
    ]

    /// The clause the model is on, or nil where the tail says nothing of the kind.
    static func extract(from text: String) -> String? {
        let tail = text.count > tailChars ? String(text.suffix(tailChars)) : text
        let chars = Array(tail)
        for sentence in endedSentences(chars).reversed() {
            if let clause = englishClause(sentence) { return clause }
        }
        return nil
    }

    // MARK: Sentences

    /// The sentences of `text` that have ended, in order. A sentence ends on a run of terminal
    /// punctuation (closing marks aside); a mark glued to a word on both sides — `build.js`,
    /// `3.14` — is not an end. The piece still growing at the tail's end has not ended.
    private static func endedSentences(_ chars: [Character]) -> [[Character]] {
        var sentences: [[Character]] = []
        var current: [Character] = []
        var pendingEnd = false
        var index = 0
        while index < chars.count {
            let char = chars[index]
            current.append(char)
            if sentenceMarks.contains(scalar(char)) {
                let next = index + 1 < chars.count ? chars[index + 1] : nil
                let glued = next.map { $0.isLetter || $0.isNumber } ?? false
                if glued {
                    index += 1
                    continue
                }
                pendingEnd = true
                index += 1
                continue
            }
            if pendingEnd {
                if closers.contains(char) || char == " " || char == "\n" || char == "\t" {
                    index += 1
                    continue
                }
                var flushed = current
                flushed.removeLast() // the character that opens the next sentence stays out of this one
                sentences.append(flushed)
                current = [char]
                pendingEnd = false
            }
            index += 1
        }
        if pendingEnd { sentences.append(current) }
        return sentences
    }

    private static func scalar(_ char: Character) -> Unicode.Scalar {
        char.unicodeScalars.first ?? " " as Unicode.Scalar
    }

    // MARK: The English clause shape

    private struct Token {
        let text: String
        let end: Int // offset in the character array, one past the last character
    }

    private enum Aspect {
        case present, perfect, either
    }

    /// The scanned copy of the sentence with the contents of every quotation blanked, so a clause
    /// is never read out of one. Same length as the sentence — offsets map one to one.
    private static func withoutQuotes(_ chars: [Character]) -> [Character] {
        var result = chars
        var index = 0
        let pairs: [Character: Character] = ["「": "」", "『": "』", "“": "”", "\"": "\""]
        while index < result.count {
            if let closer = pairs[result[index]] {
                var inner = index + 1
                while inner < result.count && result[inner] != closer {
                    result[inner] = " "
                    inner += 1
                }
                index = inner + 1
            } else {
                index += 1
            }
        }
        return result
    }

    /// Words and their end offsets: runs of letters and apostrophes (an ASCII letter, or `'` / `’`).
    private static func tokens(_ chars: [Character]) -> [Token] {
        var tokens: [Token] = []
        var start: Int?
        for index in chars.indices {
            let char = chars[index]
            let isWord = (char.isASCII && char.isLetter) || char == "'" || char == "’"
            if isWord {
                if start == nil { start = index }
            } else if let begin = start {
                tokens.append(Token(text: String(chars[begin..<index]), end: index))
                start = nil
            }
        }
        if let begin = start {
            tokens.append(Token(text: String(chars[begin..<chars.count]), end: chars.count))
        }
        return tokens
    }

    private static func auxiliary(_ token: String) -> Aspect? {
        let lower = token.lowercased()
        if let tail = contractionTail(lower) {
            switch tail {
            case "m", "re": return .present
            case "ve": return .perfect
            case "s": return .either
            default: return nil
            }
        }
        switch lower {
        case "am", "is", "are": return .present
        case "have", "has", "had": return .perfect
        default: return nil
        }
    }

    private static func contractionTail(_ token: String) -> String? {
        for tail in ["'m", "'re", "'ve", "'s", "’m", "’re", "’ve", "’s"] {
            if token.hasSuffix(tail) { return String(tail.dropFirst()) }
        }
        return nil
    }

    /// A participle: an `-ing` word the shape may anchor, the nominals left out.
    private static func isParticiple(_ token: String) -> Bool {
        let lower = token.lowercased()
        guard lower.hasSuffix("ing"), lower.count > 3 else { return false }
        guard lower.allSatisfy({ $0.isLetter && $0.isASCII }) else { return false }
        return !nominalIng.contains(lower)
    }

    /// The clause out of one English sentence, or nil where the sentence says nothing of the kind.
    private static func englishClause(_ sentence: [Character]) -> String? {
        let scanned = withoutQuotes(sentence)
        let words = tokens(scanned)
        var phrase: String?
        for index in words.indices {
            guard let head = auxiliary(words[index].text) else { continue }
            var next = index + 1
            var aspect = head
            if aspect == .either {
                let lookahead = next < words.count ? words[next].text.lowercased() : ""
                aspect = lookahead == "been" ? .perfect : .present
            }
            if aspect == .perfect {
                guard next < words.count, words[next].text.lowercased() == "been" else { continue }
                next += 1
            }
            var negated = false
            var taken = 0
            while taken < 2, next < words.count, qualifiers.contains(words[next].text.lowercased()) {
                if words[next].text.lowercased() == "not" { negated = true }
                next += 1
                taken += 1
            }
            guard !negated, next < words.count, isParticiple(words[next].text) else { continue }
            let participle = words[next].text
            let stop = scanned[words[next].end...].firstIndex(where: { clauseEnds.contains(scalar($0)) }) ?? scanned.count
            let body = stripMarkup(String(sentence[words[next].end..<stop]))
            let trimmed = trimBody(body)
            let capitalized = participle.prefix(1).uppercased() + participle.dropFirst()
            phrase = trimmed.isEmpty ? String(capitalized) : "\(capitalized) \(trimmed)"
        }
        return phrase
    }

    /// `[text](url)` → `text`, and the inline markers removed; a lone `*` or `_` stays.
    private static func stripMarkup(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for marker in ["`", "**", "__", "~~"] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        return result
    }

    /// The marks a clause carries after its stop, and repeats of spaces, collapsed.
    private static func trimBody(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: closersAndMarks)
        return trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }

    private static let closersAndMarks = CharacterSet(
        charactersIn: ".!?…。！？)]}）】》\"'“”‘’» ")
}
