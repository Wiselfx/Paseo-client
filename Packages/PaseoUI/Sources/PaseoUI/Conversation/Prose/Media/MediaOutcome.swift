#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import Synchronization
import UIKit

enum MediaOutcome: Sendable {
    case image(MediaPayload)
    /// An SVG: the caller renders it through the shared offscreen snapshot renderer, which
    /// needs a width, the colour scheme and the main actor.
    case svg(source: String, aspectRatio: CGFloat?)
    case failure(MediaFailure)
}
#endif
