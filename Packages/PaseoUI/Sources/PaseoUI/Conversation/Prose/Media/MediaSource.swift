#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import Synchronization
import UIKit

/// Where the pixels come from. One pipeline, two sources — there are never two loaders.
enum MediaSource: Hashable, Sendable {
    case remote(URL)
    case daemon(DaemonFileRef)
    /// Raw bytes with a caller-provided flight identity (the Files panel's decoded file:
    /// the bytes are already here, so the pipeline only decodes — never fetches).
    case data(Data, String)
}
#endif
