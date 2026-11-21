#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import Synchronization
import UIKit

/// A remembered failure and when it happened. `NSCache` stores objects and the card's first
/// body pass must be able to ask "did this URL fail a moment ago?" without an actor hop, so the
/// memo lives outside the actor like the decoded image does.
final class MediaFailureMemo: Sendable {
    let failure: MediaFailure
    let at: Date

    init(failure: MediaFailure, at: Date) {
        self.failure = failure
        self.at = at
    }
}
#endif
