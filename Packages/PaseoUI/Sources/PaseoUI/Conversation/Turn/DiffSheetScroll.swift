#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// The whole diff in the sheet: wrap (vertical scroll only) or scroll both ways. Upstream:
/// packages/app/src/git/diff-pane.tsx:842-847 (wrap vs scroll labels).
struct DiffSheetScroll: View {
    let lines: [ClaudeDiffLine]
    let wrap: Bool

    var body: some View {
        if wrap {
            ScrollView(.vertical) { DiffLazyLineStack(lines: lines, wrap: true) }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: .infinity)
        } else {
            ScrollView([.vertical, .horizontal]) { DiffLazyLineStack(lines: lines, wrap: false) }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: .infinity)
        }
    }
}
#endif
