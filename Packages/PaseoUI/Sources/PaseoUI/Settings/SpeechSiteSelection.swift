#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Which speech site's provider sheet is open on the Voice page. A wrapper because
/// `sheet(item:)` needs an `Identifiable` value and `SpeechSiteID` lives in another package.
struct SpeechSiteSelection: Identifiable {
    let siteID: SpeechSiteID

    var id: String { siteID.rawValue }
}
#endif
