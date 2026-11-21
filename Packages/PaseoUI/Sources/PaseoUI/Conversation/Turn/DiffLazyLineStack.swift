#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// The diff lines in a lazy column, for the whole diff in the sheet.
struct DiffLazyLineStack: View {
    let lines: [ClaudeDiffLine]
    let wrap: Bool

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in DiffLineRow(line: line, wrap: wrap) }
        }
        .padding(.vertical, 6)
        .textSelection(.enabled)
    }
}
#endif
