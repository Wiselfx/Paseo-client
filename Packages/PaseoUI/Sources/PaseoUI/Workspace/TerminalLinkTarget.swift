#if canImport(UIKit)
import PaseoStore
import QuartzCore
import SwiftTerm
import SwiftUI
import UIKit

/// Where a terminal link wants to go. Parsed from the implicit/explicit link text.
enum TerminalLinkTarget: Equatable {
    /// `path:line[:col]` — absolute, `~/` or workspace-relative. The page opens the file viewer.
    case localFile(path: String, line: Int?, col: Int?)
    /// http/https/mailto/file URLs and anything Safari can take.
    case url(URL)
    /// Nothing we can act on (a raw git SHA, a word, …).
    case unhandled(String)
}
#endif
