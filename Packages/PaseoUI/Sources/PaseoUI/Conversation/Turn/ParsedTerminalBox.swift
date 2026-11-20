#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// `NSCache` holds objects: the parse it carries.
final class ParsedTerminalBox {
    let value: ClaudeCodeBlock.ParsedTerminal
    init(value: ClaudeCodeBlock.ParsedTerminal) { self.value = value }
}
#endif
