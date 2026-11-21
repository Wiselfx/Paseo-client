#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// The diff lines in an eager column, for the few lines an inline diff shows.
struct DiffLineStack: View {
    let lines: ArraySlice<ClaudeDiffLine>
    let wrap: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in DiffLineRow(line: line, wrap: wrap) }
        }
        .padding(.vertical, 6)
        .textSelection(.enabled)
    }
}
#endif
