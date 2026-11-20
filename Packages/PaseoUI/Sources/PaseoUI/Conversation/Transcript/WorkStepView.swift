#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - One step

/// One tool step of the opened tools section, compared by value so an unchanged step is skipped.
/// Thoughts are not steps: the thought section reads them as one text.
struct WorkStepView: View, Equatable {
    let step: WorkRow
    let rail: WorkRailPosition
    let isLive: Bool
    let highlighted: Bool
    let findHit: Bool
    let onOpenFile: ((String) -> Void)?

    nonisolated static func == (lhs: WorkStepView, rhs: WorkStepView) -> Bool {
        lhs.step == rhs.step && lhs.rail == rhs.rail && lhs.isLive == rhs.isLive
            && lhs.highlighted == rhs.highlighted && lhs.findHit == rhs.findHit
    }

    var body: some View {
        switch step {
        case .tool(let row):
            if case .toolCall(let call) = row.item {
                WorkToolStep(
                    call: call, rail: rail, isLive: isLive, highlighted: highlighted,
                    findHit: findHit
                )
                .rowAnchor(row.seqEnd)
            }
        case .fileCall(let call):
            WorkFileStep(
                call: call, rail: rail, highlighted: highlighted, findHit: findHit,
                onOpenFile: onOpenFile ?? { _ in }
            )
            .rowAnchors(call.rowSeqEnds)
        case .thought:
            EmptyView()
        }
    }
}
#endif
