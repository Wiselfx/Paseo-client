#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Geometry

enum WorkTimelineMetrics {
    /// The rail's column: the nodes sit in it, the step's content starts after it.
    static let gutter: CGFloat = 28
    static let nodeSize: CGFloat = 20
    /// A step's first line: the node is centred on it.
    static let headerHeight: CGFloat = 32
    /// Air between the rail and a node.
    static let railGap: CGFloat = 3
}
extension WorkRow {
    /// Whether this step stands for the row with `seq`.
    func covers(_ seq: Int) -> Bool {
        switch self {
        case .thought(let row), .tool(let row): row.seqStart <= seq && seq <= row.seqEnd
        case .fileCall(let call): call.rowSeqEnds.contains(seq)
        }
    }

    /// Every timeline row this step stands for, as find and jump anchors.
    var seqEnds: [Int] {
        switch self {
        case .thought(let row), .tool(let row): [row.seqEnd]
        case .fileCall(let call): call.rowSeqEnds
        }
    }
}
#endif
