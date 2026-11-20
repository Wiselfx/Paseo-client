#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import Synchronization
import UIKit

/// One step of a streaming load. Size arrives first — often long before the download
/// finishes — so the card settles to its true ratio once, early, and never jumps again.
enum MediaEvent: Sendable {
    /// The true size, from the incremental probe (remote) or the header decode (daemon).
    case size(CGSize)
    /// 0…1 by 10 % buckets, only when the total is known. O(10) events per download, never
    /// per chunk: the progress ring moves without re-rendering the card per packet.
    case progress(Double)
    case final(MediaOutcome)
}
#endif
