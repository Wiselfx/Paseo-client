import Testing
@testable import PaseoUI

/// `PaseoFormat.compactCount` (D3 §4): the ticket's cases, plus the rounding edges.
/// `PaseoFormat` is UI-only, so these run wherever `PaseoUI` builds.
struct PaseoFormatTests {
    @Test func ticketCases() {
        #expect(PaseoFormat.compactCount(950) == "950")
        #expect(PaseoFormat.compactCount(1_000) == "1k")
        #expect(PaseoFormat.compactCount(1_250) == "1.3k")
        #expect(PaseoFormat.compactCount(12_400) == "12k")
        #expect(PaseoFormat.compactCount(133_900) == "134k")
        #expect(PaseoFormat.compactCount(1_200_000) == "1.2M")
    }

    @Test func oneDecimalOnlyBelowTenOfTheUnit() {
        #expect(PaseoFormat.compactCount(9_949) == "9.9k")
        #expect(PaseoFormat.compactCount(9_950) == "10k")
        #expect(PaseoFormat.compactCount(9_999_000) == "10M")
        #expect(PaseoFormat.compactCount(2_000_000) == "2M")
    }

    @Test func noTrailingZeroFraction() {
        #expect(PaseoFormat.compactCount(1_500) == "1.5k")
        #expect(PaseoFormat.compactCount(1_050) == "1.1k")
        #expect(PaseoFormat.compactCount(0) == "0")
        #expect(PaseoFormat.compactCount(999) == "999")
    }

    @Test func higherUnitsAndNegatives() {
        #expect(PaseoFormat.compactCount(18_800) == "19k")
        #expect(PaseoFormat.compactCount(1_500_000_000) == "1.5B")
        #expect(PaseoFormat.compactCount(-1_250) == "-1.3k")
    }
}
