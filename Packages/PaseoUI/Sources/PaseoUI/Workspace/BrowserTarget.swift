#if canImport(UIKit)
import Foundation

/// A page to show in the in-app browser (`SafariView`). `URL` is not `Identifiable`, so this wraps
/// it for `sheet(item:)` / `fullScreenCover(item:)`; the URL is the identity.
struct BrowserTarget: Identifiable {
    let url: URL
    var id: URL { url }
}
#endif
