#if canImport(UIKit)
import PaseoStore

/// The pairing-link acceptance rule shared by the scanner and the paste sheet: the fragment
/// markers of an offer (`ConnectionOffer`) or a `relay://` URI. The parse itself, and the real
/// validation, happen on Connect.
enum PairingLink {
    static func looksValid(_ text: String) -> Bool {
        text.contains(ConnectionOffer.offerFragmentPrefix)
            || text.contains(ConnectionOffer.connectFragmentPrefix)
            || text.hasPrefix(ConnectionOffer.relayURIScheme)
    }
}
#endif
