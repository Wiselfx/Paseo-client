#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import Synchronization
import UIKit

/// Why media did not load, phrased for the card (H5 §3: honest and useful).
enum MediaFailure: Error, Equatable, Sendable {
    case badURL
    case unsupportedScheme(String)
    case notAnImage(contentType: String?)
    case http(Int)
    case offline
    case timedOut
    /// Over a wire cap (`mediaDownloadCap`) or the hard ceiling. Carries the bytes learned
    /// so the card's tap-to-download box can show the size.
    case tooLarge(bytes: Int64?)
    case decoding
    case other

    /// One line, sentence case, no jargon the user can't act on.
    var message: String {
        switch self {
        case .badURL: "The link isn't a valid address"
        case .unsupportedScheme: "This kind of link can't be loaded"
        case .notAnImage(let contentType):
            contentType?.hasPrefix("text/html") == true
                ? "The link opened a web page, not an image" : "The link isn't an image"
        case .http(404): "The page is gone (404)"
        case .http(403): "The server refused (403)"
        case .http(let code): "The server said \(code)"
        case .offline: "No connection"
        case .timedOut: "The server didn't answer"
        case .tooLarge: "The image is too large"
        case .decoding: "The image couldn't be read"
        case .other: "The download failed"
        }
    }
}
#endif
