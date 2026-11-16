import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

/// V4 §3: the daemon's per-provider `iconSvg` (`ProviderSnapshotEntry.iconSvg`) is a whole SVG
/// document. `ProviderIcon` keeps only the geometry these marks use, so the composer chip can
/// draw the real mark instead of a monogram.
@Suite
struct ProviderIconTests {
    /// The two icons the captured providers snapshot carries (antigravity, muse). Both are one
    /// flat-coloured `path` with a `transform`, which is the shape upstream's catalogue uses.
    private func fixtureIcons() throws -> [String: String] {
        let data = try Fixture.agentControl("providers_snapshot_response")
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<GetProvidersSnapshotRequest.Response>.self, from: data
        ).payload
        var icons: [String: String] = [:]
        for entry in response.entries {
            if let svg = entry.iconSvg { icons[entry.provider] = svg }
        }
        return icons
    }

    @Test func parsesTheCataloguesRealIcons() throws {
        let icons = try fixtureIcons()
        let antigravity = try #require(icons["antigravity"])
        let muse = try #require(icons["muse"])

        let antigravityIcon = try #require(ProviderIcon.parse(antigravity))
        #expect(antigravityIcon.viewBox == ProviderIcon.Box(width: 24, height: 24))
        #expect(antigravityIcon.paths.count == 1)
        #expect(antigravityIcon.paths[0].segments.count == 8, "a move, six curves and a close")

        let museIcon = try #require(ProviderIcon.parse(muse))
        #expect(museIcon.viewBox == ProviderIcon.Box(width: 24, height: 24))
        #expect(museIcon.paths.count == 1)
    }

    /// `transform="translate(12 12) scale(0.24) translate(-55.738 -56.945)"` reads left to right:
    /// the point is translated, scaled, then translated again.
    @Test func appliesTheTransformListInReadingOrder() throws {
        let svg = try #require(fixtureIcons()["antigravity"])
        let icon = try #require(ProviderIcon.parse(svg))
        guard case .move(let start) = try #require(icon.paths.first?.segments.first) else {
            Issue.record("the antigravity mark starts with a move")
            return
        }
        // 12 + 0.24·(89.6992 − 55.738) and 12 + 0.24·(93.695 − 56.945).
        #expect(abs(start.x - 20.150_688) < 0.000_001)
        #expect(abs(start.y - 20.82) < 0.000_001)
    }

    @Test func scalesTheMuseMarkIntoItsViewBox() throws {
        let svg = try #require(fixtureIcons()["muse"])
        let icon = try #require(ProviderIcon.parse(svg))
        guard case .move(let start) = try #require(icon.paths.first?.segments.first) else {
            Issue.record("the muse mark starts with a move")
            return
        }
        #expect(abs(start.x - 24.6257 * 0.24) < 0.000_001)
        #expect(abs(start.y - 16.1214 * 0.24) < 0.000_001)
    }

    @Test func readsEverySupportedCommand() throws {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M2 2 L4 4 H6 V8 C7 7 8 8 9 9 S10 10 11 11 Q12 12 13 13 T14 14 Z"/></svg>
            """
        let icon = try #require(ProviderIcon.parse(svg))
        let segments = icon.paths[0].segments
        #expect(segments.count == 9)
        guard case .move(let origin) = segments[0] else {
            Issue.record("first segment is a move")
            return
        }
        #expect(origin == ProviderIcon.Point(x: 2, y: 2))
        guard case .line(let line) = segments[1] else {
            Issue.record("second segment is a line")
            return
        }
        #expect(line == ProviderIcon.Point(x: 4, y: 4))
        guard case .line(let horizontal) = segments[2] else {
            Issue.record("H draws a line")
            return
        }
        #expect(horizontal == ProviderIcon.Point(x: 6, y: 4))
        guard case .line(let vertical) = segments[3] else {
            Issue.record("V draws a line")
            return
        }
        #expect(vertical == ProviderIcon.Point(x: 6, y: 8))
        guard case .cubic(let c1, let c2, let end) = segments[4] else {
            Issue.record("C draws a cubic")
            return
        }
        #expect(c1 == ProviderIcon.Point(x: 7, y: 7))
        #expect(c2 == ProviderIcon.Point(x: 8, y: 8))
        #expect(end == ProviderIcon.Point(x: 9, y: 9))
        guard case .cubic(let smooth1, _, let smoothEnd) = segments[5] else {
            Issue.record("S draws a cubic")
            return
        }
        // Mirror of the previous control across (9, 9): 2·9 − 8 = 10.
        #expect(smooth1 == ProviderIcon.Point(x: 10, y: 10))
        #expect(smoothEnd == ProviderIcon.Point(x: 11, y: 11))
        guard case .quad(let control, let quadEnd) = segments[6] else {
            Issue.record("Q draws a quad")
            return
        }
        #expect(control == ProviderIcon.Point(x: 12, y: 12))
        #expect(quadEnd == ProviderIcon.Point(x: 13, y: 13))
        guard case .quad(let smoothControl, let smoothQuadEnd) = segments[7] else {
            Issue.record("T draws a quad")
            return
        }
        #expect(smoothControl == ProviderIcon.Point(x: 14, y: 14))
        #expect(smoothQuadEnd == ProviderIcon.Point(x: 14, y: 14))
        guard case .close = segments[8] else {
            Issue.record("Z closes the subpath")
            return
        }
    }

    @Test func relativeCommandsFollowTheCurrentPoint() throws {
        let svg = """
            <svg viewBox="0 0 24 24"><path d="M10 10 l5 0 h2 v3 c1 1 2 2 3 3 s1 1 2 2 q1 1 2 2 t1 1 z"/></svg>
            """
        let icon = try #require(ProviderIcon.parse(svg))
        let segments = icon.paths[0].segments
        guard case .move(let origin) = segments[0] else {
            Issue.record("first segment is a move")
            return
        }
        #expect(origin == ProviderIcon.Point(x: 10, y: 10))
        guard case .line(let relative) = segments[1] else {
            Issue.record("l draws a line")
            return
        }
        #expect(relative == ProviderIcon.Point(x: 15, y: 10))
        guard case .line(let horizontal) = segments[2] else {
            Issue.record("h draws a line")
            return
        }
        #expect(horizontal == ProviderIcon.Point(x: 17, y: 10))
        guard case .line(let vertical) = segments[3] else {
            Issue.record("v draws a line")
            return
        }
        #expect(vertical == ProviderIcon.Point(x: 17, y: 13))
        guard case .cubic(let c1, let c2, let end) = segments[4] else {
            Issue.record("c draws a cubic")
            return
        }
        #expect(c1 == ProviderIcon.Point(x: 18, y: 14))
        #expect(c2 == ProviderIcon.Point(x: 19, y: 15))
        #expect(end == ProviderIcon.Point(x: 20, y: 16))
        guard case .cubic(_, _, let smoothEnd) = segments[5] else {
            Issue.record("s draws a cubic")
            return
        }
        #expect(smoothEnd == ProviderIcon.Point(x: 22, y: 18))
        guard case .quad(_, let quadEnd) = segments[6] else {
            Issue.record("q draws a quad")
            return
        }
        #expect(quadEnd == ProviderIcon.Point(x: 24, y: 20))
        guard case .quad(_, let smoothQuadEnd) = segments[7] else {
            Issue.record("t draws a quad")
            return
        }
        #expect(smoothQuadEnd == ProviderIcon.Point(x: 25, y: 21))
    }

    @Test func keepsSeveralPathsAndSkipsStrokedOnes() throws {
        let svg = """
            <svg viewBox="0 0 16 16"><path fill="currentColor" d="M1 1 L2 2 Z"/><path fill="none" stroke="currentColor" d="M3 3 L4 4"/><path d="M5 5 L6 6 Z"/></svg>
            """
        let icon = try #require(ProviderIcon.parse(svg))
        #expect(icon.paths.count == 2, "the stroked outline is not part of the filled mark")
    }

    @Test func readsTheBoxFromWidthAndHeightWhenThereIsNoViewBox() throws {
        let svg = #"<svg width="16" height="16"><path d="M0 0 L16 16 Z"/></svg>"#
        let icon = try #require(ProviderIcon.parse(svg))
        #expect(icon.viewBox == ProviderIcon.Box(width: 16, height: 16))
    }

    @Test func rejectsGeometryItCannotDraw() {
        // Arcs, shapes other than `path`, and transforms outside translate/scale/matrix/rotate.
        let arcs = #"<svg viewBox="0 0 24 24"><path d="M2 2 A4 4 0 0 1 6 6 Z"/></svg>"#
        #expect(ProviderIcon.parse(arcs) == nil)
        let circle = #"<svg viewBox="0 0 24 24"><circle cx="8" cy="8" r="7"/></svg>"#
        #expect(ProviderIcon.parse(circle) == nil)
        let skew = #"<svg viewBox="0 0 24 24"><path transform="skewX(10)" d="M2 2 L3 3 Z"/></svg>"#
        #expect(ProviderIcon.parse(skew) == nil)
        let noBox = #"<svg><path d="M2 2 L3 3 Z"/></svg>"#
        #expect(ProviderIcon.parse(noBox) == nil)
        #expect(ProviderIcon.parse("") == nil)
    }
}
