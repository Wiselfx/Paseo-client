import Foundation

/// A provider's mark, parsed from the `iconSvg` its catalogue entry carries
/// (`ProviderSnapshotEntry.iconSvg`).
///
/// The daemon ships a whole SVG document per provider. Rendering one on the device would mean a
/// web view or a full SVG engine, so this type keeps only the geometry the marks actually use:
/// single-colour `path` outlines in a view box, filled by the caller in the ink colour. Anything
/// outside that subset (strokes, gradients, `text`/`circle`/`rect` shapes, arc segments) makes
/// `parse` return nil, and the caller keeps its monogram fallback.
public struct ProviderIcon: Sendable, Hashable {
    /// A point in view-box coordinates.
    public struct Point: Sendable, Hashable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// The `viewBox` rectangle the paths are drawn in.
    public struct Box: Sendable, Hashable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double = 0, y: Double = 0, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// One drawing command, in view-box coordinates, with the path's `transform` already applied.
    public enum Segment: Sendable, Hashable {
        case move(Point)
        case line(Point)
        case cubic(control1: Point, control2: Point, end: Point)
        case quad(control: Point, end: Point)
        case close
    }

    public struct Path: Sendable, Hashable {
        public var segments: [Segment]

        public init(segments: [Segment]) {
            self.segments = segments
        }
    }

    public var viewBox: Box
    /// Filled separately; every path is the same ink, so their union is the mark.
    public var paths: [Path]

    public init(viewBox: Box, paths: [Path]) {
        self.viewBox = viewBox
        self.paths = paths
    }

    /// Parses an SVG document. Returns nil when the document holds no drawable `path`, or uses
    /// geometry this renderer does not implement.
    public static func parse(_ svg: String) -> ProviderIcon? {
        guard let svgTag = openTag(named: "svg", in: svg) else { return nil }
        let root = attributes(in: svgTag)
        guard let viewBox = viewBox(from: root) else { return nil }

        var paths: [Path] = []
        var search = svg.startIndex
        while let open = svg.range(of: "<path", range: search..<svg.endIndex) {
            guard let end = svg[open.upperBound...].firstIndex(of: ">") else { return nil }
            search = svg.index(after: end)
            let attributes = attributes(in: svg[open.upperBound..<end])
            // Stroked outlines (grids, rules) are not part of the mark; filling them would smear
            // a solid block over the glyph.
            if attributes["fill"]?.lowercased() == "none" { continue }
            guard let data = attributes["d"], let transform = affine(attributes["transform"])
            else { return nil }
            guard let segments = segments(from: data, transform: transform), !segments.isEmpty
            else { return nil }
            paths.append(Path(segments: segments))
        }
        guard !paths.isEmpty else { return nil }
        return ProviderIcon(viewBox: viewBox, paths: paths)
    }
}

// MARK: - Document scanning

extension ProviderIcon {
    /// The opening tag of the first `name` element (`<svg …>`), without the angle brackets.
    private static func openTag(named name: String, in document: String) -> Substring? {
        let opening = "<\(name)"
        var search = document.startIndex
        while let range = document.range(of: opening, range: search..<document.endIndex) {
            let after = range.upperBound
            // `<svgfoo` is a different element.
            guard after == document.endIndex || !isNameCharacter(document[after]) else {
                search = after
                continue
            }
            guard let end = document[after...].firstIndex(of: ">") else { return nil }
            return document[after..<end]
        }
        return nil
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_"
    }

    /// `key="value"` pairs inside a tag body. Attribute order is irrelevant; keys are lowercased
    /// because SVG writers disagree on `viewBox`/`viewbox`.
    private static func attributes(in tag: Substring) -> [String: String] {
        var result: [String: String] = [:]
        var rest = tag
        while let equals = rest.firstIndex(of: "=") {
            let key = rest[rest.startIndex..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = rest[rest.index(after: equals)...]
            guard let quote = value.first, quote == "\"" || quote == "'" else { break }
            value = value.dropFirst()
            guard let end = value.firstIndex(of: quote) else { break }
            if !key.isEmpty { result[key.lowercased()] = String(value[value.startIndex..<end]) }
            rest = value[value.index(after: end)...]
        }
        return result
    }

    private static func viewBox(from root: [String: String]) -> Box? {
        if let raw = root["viewbox"], let values = numbers(in: raw), values.count == 4,
            values[2] > 0, values[3] > 0
        {
            return Box(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        // No viewBox: the width/height attributes are the box's size at the origin.
        if let width = root["width"].flatMap(Double.init), let height = root["height"].flatMap(Double.init),
            width > 0, height > 0
        {
            return Box(width: width, height: height)
        }
        return nil
    }

    /// Every number in a `transform` or `viewBox` value, in order.
    private static func numbers(in text: String) -> [Double]? {
        let characters = Array(text)
        var index = 0
        var result: [Double] = []
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace || character == "," {
                index += 1
                continue
            }
            guard let value = scanNumber(characters, &index) else { return nil }
            result.append(value)
        }
        return result
    }
}

// MARK: - Transforms

extension ProviderIcon {
    /// `x' = a·x + c·y + e`, `y' = b·x + d·y + f` — the SVG transform matrix.
    struct Affine: Sendable, Hashable {
        var a: Double
        var b: Double
        var c: Double
        var d: Double
        var e: Double
        var f: Double

        static let identity = Affine(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)

        init(a: Double, b: Double, c: Double, d: Double, e: Double, f: Double) {
            self.a = a
            self.b = b
            self.c = c
            self.d = d
            self.e = e
            self.f = f
        }

        func applying(_ point: Point) -> Point {
            Point(x: a * point.x + c * point.y + e, y: b * point.x + d * point.y + f)
        }

        /// `lhs·rhs`: `rhs` applies to the point first, `lhs` second. A transform list reads left
        /// to right, so the list folds from the left through this product.
        static func * (lhs: Affine, rhs: Affine) -> Affine {
            Affine(
                a: lhs.a * rhs.a + lhs.c * rhs.b,
                b: lhs.b * rhs.a + lhs.d * rhs.b,
                c: lhs.a * rhs.c + lhs.c * rhs.d,
                d: lhs.b * rhs.c + lhs.d * rhs.d,
                e: lhs.a * rhs.e + lhs.c * rhs.f + lhs.e,
                f: lhs.b * rhs.e + lhs.d * rhs.f + lhs.f)
        }

        /// One `name(args)` step; nil for a name this renderer does not implement.
        init?(name: String, arguments: [Double]) {
            switch name {
            case "translate":
                guard arguments.count == 1 || arguments.count == 2 else { return nil }
                self.init(
                    a: 1, b: 0, c: 0, d: 1, e: arguments[0],
                    f: arguments.count == 2 ? arguments[1] : 0)
            case "scale":
                guard arguments.count == 1 || arguments.count == 2 else { return nil }
                self.init(
                    a: arguments[0], b: 0, c: 0, d: arguments.count == 2 ? arguments[1] : arguments[0],
                    e: 0, f: 0)
            case "matrix":
                guard arguments.count == 6 else { return nil }
                self.init(
                    a: arguments[0], b: arguments[1], c: arguments[2], d: arguments[3],
                    e: arguments[4], f: arguments[5])
            case "rotate":
                guard arguments.count == 1 || arguments.count == 3 else { return nil }
                let radians = arguments[0] * .pi / 180
                let rotation = Affine(
                    a: cos(radians), b: sin(radians), c: -sin(radians), d: cos(radians), e: 0, f: 0)
                guard arguments.count == 3 else {
                    self = rotation
                    return
                }
                let toCenter = Affine(a: 1, b: 0, c: 0, d: 1, e: arguments[1], f: arguments[2])
                let back = Affine(a: 1, b: 0, c: 0, d: 1, e: -arguments[1], f: -arguments[2])
                self = toCenter * rotation * back
            default:
                return nil
            }
        }
    }

    /// The full `transform` attribute, folded left to right. Missing means identity; malformed
    /// or unsupported means nil (and the whole icon falls back to the monogram).
    private static func affine(_ text: String?) -> Affine? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .identity
        }
        var result = Affine.identity
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace || character == "," {
                index = text.index(after: index)
                continue
            }
            guard let open = text[index...].firstIndex(of: "("),
                let close = text[open...].firstIndex(of: ")")
            else { return nil }
            let name = text[index..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let arguments = numbers(in: String(text[text.index(after: open)..<close])),
                let step = Affine(name: name.lowercased(), arguments: arguments)
            else { return nil }
            result = result * step
            index = text.index(after: close)
        }
        return result
    }
}

// MARK: - Path data

extension ProviderIcon {
    /// The supported command letters: absolute and relative move, line, horizontal, vertical,
    /// cubic, smooth cubic, quadratic, smooth quadratic and close. Arcs (`A`/`a`) and anything
    /// else unsupported make the whole icon unparseable.
    private static let commands: Set<Character> = [
        "M", "m", "L", "l", "H", "h", "V", "v", "C", "c", "S", "s", "Q", "q", "T", "t", "Z", "z",
    ]

    private static func segments(from data: String, transform: Affine) -> [Segment]? {
        let characters = Array(data)
        var index = 0
        var result: [Segment] = []
        // The current point in *path* coordinates; every emitted point is transformed once, so
        // relative deltas stay relative to the untransformed point.
        var raw = Point(x: 0, y: 0)
        var subpathStart = Point(x: 0, y: 0)
        var lastCubicControl: Point?
        var lastQuadControl: Point?
        var command: Character?

        func skipSeparators() {
            while index < characters.count,
                characters[index].isWhitespace || characters[index] == ","
            {
                index += 1
            }
        }

        func emit(_ segment: Segment) { result.append(segment) }

        while true {
            skipSeparators()
            guard index < characters.count else { break }
            let next = characters[index]
            if next.isLetter {
                guard commands.contains(next) else { return nil }
                command = next
                index += 1
            } else if let current = command, current == "M" {
                // A second coordinate pair after a move is an implicit line.
                command = "L"
            } else if let current = command, current == "m" {
                command = "l"
            } else if command == nil {
                return nil
            }
            guard let active = command else { return nil }

            switch active {
            case "M", "m", "L", "l":
                guard let x = scanNumber(characters, &index), let y = scanNumber(characters, &index)
                else { return nil }
                let relative = active == "m" || active == "l"
                raw = relative
                    ? Point(x: raw.x + x, y: raw.y + y)
                    : Point(x: x, y: y)
                if active == "M" || active == "m" {
                    emit(.move(transform.applying(raw)))
                    subpathStart = raw
                } else {
                    emit(.line(transform.applying(raw)))
                }
                lastCubicControl = nil
                lastQuadControl = nil
            case "H", "h", "V", "v":
                guard let value = scanNumber(characters, &index) else { return nil }
                let relative = active == "h" || active == "v"
                switch active {
                case "H", "h":
                    raw = Point(x: relative ? raw.x + value : value, y: raw.y)
                default:
                    raw = Point(x: raw.x, y: relative ? raw.y + value : value)
                }
                emit(.line(transform.applying(raw)))
                lastCubicControl = nil
                lastQuadControl = nil
            case "C", "c", "S", "s":
                let relative = active == "c" || active == "s"
                var control1: Point
                if active == "C" || active == "c" {
                    guard let x1 = scanNumber(characters, &index), let y1 = scanNumber(characters, &index)
                    else { return nil }
                    control1 = Point(x: x1, y: y1)
                } else if let previous = lastCubicControl {
                    // Smooth cubic: mirror the previous control across the current point.
                    control1 = Point(x: 2 * raw.x - previous.x, y: 2 * raw.y - previous.y)
                } else {
                    control1 = raw
                }
                guard let x2 = scanNumber(characters, &index), let y2 = scanNumber(characters, &index),
                    let x = scanNumber(characters, &index), let y = scanNumber(characters, &index)
                else { return nil }
                let control2 = Point(x: x2, y: y2)
                let end = Point(x: x, y: y)
                let resolved = relative ? shifted(control1, control2, end, by: raw) : (control1, control2, end)
                raw = resolved.2
                lastCubicControl = resolved.1
                lastQuadControl = nil
                emit(
                    .cubic(
                        control1: transform.applying(resolved.0),
                        control2: transform.applying(resolved.1),
                        end: transform.applying(resolved.2)))
            case "Q", "q", "T", "t":
                let relative = active == "q" || active == "t"
                var control: Point
                if active == "Q" || active == "q" {
                    guard let x1 = scanNumber(characters, &index), let y1 = scanNumber(characters, &index)
                    else { return nil }
                    control = Point(x: x1, y: y1)
                } else if let previous = lastQuadControl {
                    control = Point(x: 2 * raw.x - previous.x, y: 2 * raw.y - previous.y)
                } else {
                    control = raw
                }
                guard let x = scanNumber(characters, &index), let y = scanNumber(characters, &index)
                else { return nil }
                let end = Point(x: x, y: y)
                if relative {
                    control = Point(x: control.x + raw.x, y: control.y + raw.y)
                    raw = Point(x: end.x + raw.x, y: end.y + raw.y)
                } else {
                    raw = end
                }
                lastQuadControl = control
                lastCubicControl = nil
                emit(.quad(control: transform.applying(control), end: transform.applying(raw)))
            case "Z", "z":
                raw = subpathStart
                lastCubicControl = nil
                lastQuadControl = nil
                emit(.close)
                // A close repeats as a no-op until the next command.
                command = nil
            default:
                return nil
            }
        }
        return result
    }

    /// Relative cubic operands: every point moves by the current point.
    private static func shifted(
        _ control1: Point, _ control2: Point, _ end: Point, by origin: Point
    ) -> (Point, Point, Point) {
        (
            Point(x: control1.x + origin.x, y: control1.y + origin.y),
            Point(x: control2.x + origin.x, y: control2.y + origin.y),
            Point(x: end.x + origin.x, y: end.y + origin.y)
        )
    }
}

// MARK: - Number scanning

/// Reads one number (sign, digits, fraction, exponent) starting at `index`, skipping leading
/// separators. Advances `index` past it.
private func scanNumber(_ characters: [Character], _ index: inout Int) -> Double? {
    while index < characters.count, characters[index].isWhitespace || characters[index] == "," {
        index += 1
    }
    let start = index
    if index < characters.count, characters[index] == "+" || characters[index] == "-" {
        index += 1
    }
    var sawDigit = false
    while index < characters.count, characters[index].isNumber {
        index += 1
        sawDigit = true
    }
    if index < characters.count, characters[index] == "." {
        index += 1
        while index < characters.count, characters[index].isNumber {
            index += 1
            sawDigit = true
        }
    }
    if sawDigit, index < characters.count, characters[index] == "e" || characters[index] == "E" {
        let beforeExponent = index
        index += 1
        if index < characters.count, characters[index] == "+" || characters[index] == "-" {
            index += 1
        }
        var sawExponentDigit = false
        while index < characters.count, characters[index].isNumber {
            index += 1
            sawExponentDigit = true
        }
        if !sawExponentDigit { index = beforeExponent }
    }
    guard sawDigit, let value = Double(String(characters[start..<index])) else {
        index = start
        return nil
    }
    return value
}
