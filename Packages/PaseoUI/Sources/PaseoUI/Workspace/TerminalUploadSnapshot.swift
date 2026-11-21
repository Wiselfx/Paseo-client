#if canImport(UIKit)
import SwiftTerm
import SwiftUI
import UIKit

/// One-line snapshot of an in-flight T14 (`file.upload`) transfer, for the key bar's progress
/// row. `progress` is 0…1 bytes-sent; the daemon answers only after all bytes arrive.
struct TerminalUploadSnapshot: Equatable {
    let fileName: String
    let progress: Double
}
#endif
