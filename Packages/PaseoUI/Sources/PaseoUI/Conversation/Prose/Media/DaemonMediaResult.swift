#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import Synchronization
import UIKit

/// What a daemon read resolves to. `tooLarge` is the daemon refusing `maxBytes` (it stats
/// the file first and never transfers it); `unavailable` is everything else.
///
/// The refusal arrives as `PaseoStoreError.missingFile` carrying the daemon's own text
/// ("File is too large to display" on the frozen reference); matching it is upstream-
/// string-dependent and documented at the single mapping site, in the controller.
enum DaemonMediaResult: Sendable {
    case bytes(DaemonFileBytes)
    case tooLarge
    case unavailable
}
#endif
