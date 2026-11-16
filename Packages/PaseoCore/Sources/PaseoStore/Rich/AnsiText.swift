import Foundation

// MARK: - AnsiText (G8 C12)

// NOTE: RemoteImagePipeline/G8: shell output keeps its colors but is truncated to the
// tail. Only SGR (Select Graphic Rendition) survives parsing: cursor movement and every
// other escape is dropped, so no raw escape ever reaches the screen. Runs merge while
// parsing, so the array stays proportional to style changes, not to bytes.

// NOTE: RemoteImagePipeline/G8: the terminal is presentation, not emulation. A
// per-tool-call xterm (SwiftTerm) would cost a process per call for output that is
// already finished text; SGR runs cover the color that carries meaning.

/// One run of plain text in one style. Styles compare by value, so adjacent runs with
/// the same style merge during the parse.
public struct AnsiRun: Sendable, Equatable, Hashable {
    public var text: String
    public var style: AnsiStyle

    public init(text: String, style: AnsiStyle = AnsiStyle()) {
        self.text = text
        self.style = style
    }
}

/// The SGR subset that reaches the screen. Everything else (cursor movement, scrolling,
/// clearing, OSC hyperlinks) is dropped by the parser.
public struct AnsiStyle: Sendable, Equatable, Hashable {
    /// `nil` renders the theme's prose ink.
    public var foreground: AnsiColor?
    public var background: AnsiColor?
    public var bold = false
    public var dim = false
    public var underline = false
    public var strikethrough = false

    public init(
        foreground: AnsiColor? = nil, background: AnsiColor? = nil, bold: Bool = false,
        dim: Bool = false, underline: Bool = false, strikethrough: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.dim = dim
        self.underline = underline
        self.strikethrough = strikethrough
    }

    /// The empty style: prose ink, no emphasis.
    public static let plain = AnsiStyle()
}

/// The 16 terminal colors, by SGR number. 256-color and truecolor sequences quantize
/// to these (the card draws them from `Palette.ansi*`, one token per slot).
public enum AnsiColor: Int, Sendable, Equatable, Hashable, CaseIterable {
    case black = 0, red, green, yellow, blue, magenta, cyan, white
    case brightBlack = 8, brightRed, brightGreen, brightYellow, brightBlue, brightMagenta,
        brightCyan, brightWhite

    /// `30`–`37` / `90`–`97` (foreground) and `40`–`47` / `100`–`107` (background).
    static func standard(code: Int, bright: Bool) -> AnsiColor? {
        let base = code - (bright ? 90 : 30)
        guard (0..<8).contains(base) else { return nil }
        return AnsiColor(rawValue: base + (bright ? 8 : 0))
    }

    /// The xterm 256 palette, slot by slot: 0–15 are the 16, 16–231 the 6×6×6 cube,
    /// 232–255 the grayscale ramp.
    static func xterm256(_ n: Int) -> AnsiColor? {
        switch n {
        case 0..<16: return AnsiColor(rawValue: n)
        case 16..<232:
            let v = n - 16
            let r = v / 36, g = (v % 36) / 6, b = v % 6
            return nearest(red: r * 51, green: g * 51, blue: b * 51)
        case 232..<256:
            let level = 8 + (n - 232) * 10
            return nearest(red: level, green: level, blue: level)
        default: return nil
        }
    }

    /// Truecolor quantizes to the nearest of the 16 by squared RGB distance.
    static func truecolor(red: Int, green: Int, blue: Int) -> AnsiColor {
        nearest(red: red, green: green, blue: blue)
    }

    private static let rgb: [(Int, Int, Int)] = [
        (0, 0, 0), (170, 0, 0), (0, 170, 0), (170, 85, 0),
        (0, 0, 170), (170, 0, 170), (0, 170, 170), (170, 170, 170),
        (85, 85, 85), (255, 85, 85), (85, 255, 85), (255, 255, 85),
        (85, 85, 255), (255, 85, 255), (85, 255, 255), (255, 255, 255),
    ]

    private static func nearest(red: Int, green: Int, blue: Int) -> AnsiColor {
        var best = AnsiColor.white
        var bestDistance = Int.max
        for (index, (r, g, b)) in rgb.enumerated() {
            let dr = r - red, dg = g - green, db = b - blue
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = AnsiColor(rawValue: index) ?? .white
            }
        }
        return best
    }
}

/// SGR → runs. Single pass, O(input): state changes only on escape sequences, text
/// appends to the open run, and adjacent same-style runs merge. `\r` resets the line
/// buffer (carriage-return progress bars), so a spinner never multiplies lines.
public enum AnsiText {
    public static func parse(_ input: String) -> [AnsiRun] {
        // Bytes, not `String` indices: per-character index arithmetic dominates the cost
        // at 1 MB, while every decision point here is ASCII. Splits only ever land on
        // ASCII control bytes, so multibyte text is never cut mid-character.
        let bytes = Array(input.utf8)
        var runs: [AnsiRun] = []
        var style = AnsiStyle()
        var textStart = 0
        var cursor = 0

        func flush(through end: Int) {
            guard end > textStart else { return }
            let text = String(decoding: bytes[textStart..<end], as: UTF8.self)
            if let last = runs.last, last.style == style {
                runs[runs.count - 1].text += text
            } else {
                runs.append(AnsiRun(text: text, style: style))
            }
            textStart = end
        }

        while cursor < bytes.count {
            let byte = bytes[cursor]
            if byte == 0x1B {  // ESC
                // Emit what precedes the escape first: the bytes of the escape itself
                // are skipped by moving textStart past them, never flushed.
                flush(through: cursor)
                if cursor + 1 < bytes.count, bytes[cursor + 1] == 0x5B {  // [
                    if let (params, final, after) = parseCSI(bytes, from: cursor + 2) {
                        if final == 0x6D {  // m
                            flush(through: cursor)
                            applySGR(params, to: &style)
                        }
                        // Every other CSI (cursor movement, scrolling, clearing,
                        // line/character ops) is dropped.
                        textStart = after
                        cursor = after
                        continue
                    }
                    textStart = cursor + 1
                    cursor += 2
                    continue
                }
                if cursor + 1 < bytes.count, bytes[cursor + 1] == 0x5D {  // ]
                    // OSC (hyperlinks, titles) is dropped through its terminator, but the
                    // link text between stays.
                    let after = skipOSC(bytes, from: cursor + 2)
                    textStart = after
                    cursor = after
                    continue
                }
                // Any other escape (charset switches and friends): the introducer goes,
                // printable text stays.
                textStart = cursor + 1
                cursor += 1
                continue
            }
            if byte == 0x0D {  // CR
                // Carriage return: the line redraws from the column start.
                textStart = cursor + 1
                cursor += 1
                continue
            }
            if byte == 0x0A {  // LF
                cursor += 1
                flush(through: cursor)
                continue
            }
            cursor += 1
        }
        flush(through: bytes.count)
        return runs
    }


    /// The runs covering the last `maxLines` lines, in order. The tail card parses the
    /// whole output once and shows this slice; "Show all" shows the rest. Line
    /// terminators ride with the line they end (a lone-newline run never counts as a
    /// line of its own), so a style change at a boundary cannot shift the cut.
    public static func tail(_ runs: [AnsiRun], maxLines: Int) -> [AnsiRun] {
        guard maxLines > 0 else { return [] }
        // Forward split into lines: each line is the runs covering its content.
        var lines: [[AnsiRun]] = [[]]
        for run in runs {
            let parts = run.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                if index > 0 { lines.append([]) }
                if !part.isEmpty {
                    lines[lines.count - 1].append(AnsiRun(text: String(part), style: run.style))
                }
            }
        }
        // A final newline terminates the last line; it does not start a new one.
        if let last = lines.last, last.isEmpty { lines.removeLast() }
        let endedWithNewline = runs.last?.text.hasSuffix("\n") == true
        // Re-emit the kept suffix; terminators join the preceding run (newlines
        // have no glyph, so their style is invisible either way).
        var out: [AnsiRun] = []
        func emit(_ text: String, style: AnsiStyle) {
            guard !text.isEmpty else { return }
            if out.last?.style == style {
                out[out.count - 1].text += text
            } else {
                out.append(AnsiRun(text: text, style: style))
            }
        }
        // A suffix always reaches the true end, so the final kept line keeps the
        // original's trailing newline when there was one.
        let kept = lines.suffix(maxLines)
        for (lineIndex, line) in kept.enumerated() {
            for run in line { emit(run.text, style: run.style) }
            let terminated = lineIndex < kept.count - 1 || endedWithNewline
            if terminated {
                if let last = out.last {
                    out[out.count - 1].text = last.text + "\n"
                } else {
                    out.append(AnsiRun(text: "\n", style: .plain))
                }
            }
        }
        return out
    }

    /// The bytes for Copy: no escapes, no styles, carriage returns resolved.
    public static func plainText(_ input: String) -> String {
        parse(input).map(\.text).joined()
    }

    /// The last lines of raw output without parsing ANSI: a byte walks back over
    /// the last `maxLines` newlines, then a cheap byte filter strips `ESC`
    /// sequences (CSI, OSC, lone `ESC` + byte). The terminal card's first-pass
    /// placeholder: the final box height with no parse. O(tail) — never the whole
    /// megabyte. A single trailing newline terminates the last line (as `tail`
    /// does); it does not add a line.
    public static func plainTail(_ input: String, maxLines: Int) -> String {
        guard maxLines > 0, !input.isEmpty else { return "" }
        let bytes = Array(input.utf8)
        var end = bytes.count
        if end > 0, bytes[end - 1] == 0x0A { end -= 1 }
        var start = 0
        var lines = 0
        var index = end - 1
        while index >= 0 {
            if bytes[index] == 0x0A {
                lines += 1
                if lines >= maxLines {
                    start = index + 1
                    break
                }
            }
            index -= 1
        }
        var out = [UInt8]()
        out.reserveCapacity(bytes.count - start)
        var cursor = start
        while cursor < bytes.count {
            let byte = bytes[cursor]
            guard byte == 0x1B else {
                out.append(byte)
                cursor += 1
                continue
            }
            cursor += 1
            guard cursor < bytes.count else { break }
            if bytes[cursor] == 0x5B {
                // CSI: `ESC [ params… final` — the final byte is 0x40…0x7E.
                cursor += 1
                while cursor < bytes.count,
                    !(bytes[cursor] >= 0x40 && bytes[cursor] <= 0x7E)
                {
                    cursor += 1
                }
                cursor += 1
            } else if bytes[cursor] == 0x5D {
                // OSC: `ESC ] … BEL` or `… ESC \`.
                cursor += 1
                while cursor < bytes.count {
                    if bytes[cursor] == 0x07 {
                        cursor += 1
                        break
                    }
                    if bytes[cursor] == 0x1B, cursor + 1 < bytes.count,
                        bytes[cursor + 1] == 0x5C
                    {
                        cursor += 2
                        break
                    }
                    cursor += 1
                }
            } else {
                cursor += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: Sequences

    /// `ESC [ params final` → the integer params, the final byte, and the index after it.
    /// Non-numeric intermediates (`?25l`, `;` runs, `:` sub-params) parse leniently:
    /// a bare `ESC[m` is `[0]`, `1;` does not append a phantom reset. Unbounded length
    /// is clamped by the loop ending at the final byte.
    private static func parseCSI(_ bytes: [UInt8], from start: Int) -> (params: [Int], final: UInt8, after: Int)? {
        var index = start
        var current = 0
        var hasDigits = false
        var params: [Int] = []
        var sawDigit = false
        while index < bytes.count {
            let byte = bytes[index]
            if byte >= 0x30, byte <= 0x39 {
                current = current * 10 + Int(byte - 0x30)
                hasDigits = true
                sawDigit = true
            } else if byte == 0x3B || byte == 0x3A {  // ; :
                params.append(hasDigits ? current : 0)
                current = 0
                hasDigits = false
            } else if byte >= 0x40, byte <= 0x7E {
                if sawDigit {
                    params.append(current)
                } else if params.isEmpty {
                    params = [0]
                }
                return (params, byte, index + 1)
            } else {
                // Private markers (`?`, `>`, `!`, …): ignored.
            }
            index += 1
        }
        return nil
    }

    private static func skipOSC(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count {
            if bytes[index] == 0x07 { return index + 1 }  // BEL
            if bytes[index] == 0x1B, index + 1 < bytes.count, bytes[index + 1] == 0x5C {
                return index + 2  // ESC \
            }
            index += 1
        }
        return index
    }

    private static func applySGR(_ params: [Int], to style: inout AnsiStyle) {
        // A bare `ESC[m` is a reset.
        let list = params.isEmpty ? [0] : params
        var index = list.startIndex
        func take() -> Int {
            guard index < list.endIndex else { return 0 }
            defer { index = list.index(after: index) }
            return list[index]
        }
        while index < list.endIndex {
            let code = take()
            switch code {
            case 0: style = AnsiStyle()
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: break
            case 4: style.underline = true
            case 9: style.strikethrough = true
            case 22: style.bold = false; style.dim = false
            case 23, 24, 29: break
            case 30..<38: style.foreground = AnsiColor.standard(code: code, bright: false)
            case 39: style.foreground = nil
            case 40..<48:
                if let color = AnsiColor(rawValue: code - 40) { style.background = color }
            case 49: style.background = nil
            case 90..<98: style.foreground = AnsiColor.standard(code: code, bright: true)
            case 100..<108:
                style.background = AnsiColor(rawValue: code - 100 + 8)
            case 38, 48:
                let isForeground = code == 38
                let mode = take()
                if mode == 5 {
                    let color = AnsiColor.xterm256(take())
                    if isForeground { style.foreground = color } else { style.background = color }
                } else if mode == 2 {
                    let color = AnsiColor.truecolor(red: take(), green: take(), blue: take())
                    if isForeground { style.foreground = color } else { style.background = color }
                }
            default: break
            }
        }
    }
}
