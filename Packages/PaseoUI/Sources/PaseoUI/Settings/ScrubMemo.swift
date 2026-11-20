#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Remembers the last scrubbed bundle for the input it came from.
@MainActor final class ScrubMemo {
    private var input: String?
    private var output = ""

    func scrubbed(_ text: String) -> String {
        if input == text { return output }
        output = DiagnosticsPage.scrubHostDiagnostic(text)
        input = text
        return output
    }
}
#endif
