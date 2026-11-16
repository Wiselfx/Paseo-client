import Foundation
import Testing
@testable import PaseoStore

/// M17: strict standalone map references. Doc 05 specifies no map rule, so these encode
/// the §1.1-shaped rule the detector implements: standalone line only, never lists, and
/// no address guessing — prose never becomes a map card.
@Suite struct MapDetectorTests {
    private func detected(_ source: String) -> [RichContentBlock] {
        RichContentDetector.detect(in: source)
    }

    private func mapCard(_ source: String) -> MapReference? {
        for block in detected(source) {
            if case .mapCard(let reference, _) = block { return reference }
        }
        return nil
    }

    @Test func standaloneCoordinatePairYieldsMapCard() {
        let reference = mapCard("37.7749, -122.4194")
        #expect(reference?.latitude == 37.7749)
        #expect(reference?.longitude == -122.4194)
    }

    @Test func geoURIYieldsMapCard() {
        let reference = mapCard("geo:51.5074,-0.1278")
        #expect(reference?.latitude == 51.5074)
        #expect(reference?.longitude == -0.1278)
    }

    @Test func appleMapsURLYieldsMapCardWithCoordinates() {
        let reference = mapCard("https://maps.apple.com/?ll=37.7749,-122.4194")
        #expect(reference?.latitude == 37.7749)
        #expect(reference?.longitude == -122.4194)
    }

    @Test func googleMapsURLYieldsMapCard() {
        let reference = mapCard("https://www.google.com/maps/@40.7128,-74.006,15z")
        #expect(reference?.latitude == 40.7128)
        #expect(reference?.longitude == -74.006)
    }

    @Test func queryOnlyMapsURLYieldsMapCardWithoutCoordinates() {
        let reference = mapCard("https://maps.apple.com/?q=coffee")
        #expect(reference != nil)
        #expect(reference?.latitude == nil)
    }

    @Test func mapsURLBeatsLinkCard() {
        let blocks = detected("https://maps.apple.com/?ll=37.7,-122.4")
        #expect(blocks.count == 1)
        #expect(mapCard("https://maps.apple.com/?ll=37.7,-122.4") != nil)
        #expect(!blocks.contains { if case .linkCard = $0 { true } else { false } })
    }

    @Test func coordinatesInProseStayProse() {
        #expect(mapCard("The office is at 37.7749, -122.4194 downtown") == nil)
    }

    @Test func streetAddressNeverBecomesAMap() {
        #expect(mapCard("Meet at 1600 Amphitheatre Parkway, Mountain View") == nil)
        #expect(detected("Meet at 1600 Amphitheatre Parkway").isEmpty)
    }

    @Test func yearPairsAndOutOfRangeStayProse() {
        #expect(mapCard("2024, 2025") == nil)
        #expect(mapCard("95.0, 999.0") == nil)
    }

    @Test func coordinateInListStaysProse() {
        #expect(mapCard("- 37.7749, -122.4194") == nil)
    }

    @Test func coordinateInCodeStaysProse() {
        let source = "`37.7749, -122.4194`"
        #expect(mapCard(source) == nil)
    }
}
