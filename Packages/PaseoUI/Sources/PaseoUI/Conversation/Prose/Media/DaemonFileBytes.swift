#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import Synchronization
import UIKit

/// Raw daemon bytes plus the revision the daemon reported, if any. The controller builds
/// this from `checkout.files.fetch(path, maxBytes:)`; the pipeline owns everything after.
struct DaemonFileBytes: Sendable {
    var data: Data
    var revision: String?
}
#endif
