#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The opened tool section: its calls on a hairline rail, newest last. Built only while the
/// section is open.
struct WorkToolSteps: View {
    let steps: [WorkRow]
    let showsEarlier: Bool
    let foldThreshold: Int
    let keptSteps: Int
    /// The run is the turn's live tail: its last step is the one happening now.
    let isLiveTail: Bool
    var highlightedSeq: Int?
    var findTarget: Int?
    var onOpenFile: ((String) -> Void)?
    let onShowEarlier: () -> Void

    private var hidden: Int {
        !showsEarlier && steps.count > foldThreshold ? steps.count - keptSteps : 0
    }

    var body: some View {
        let hidden = hidden
        VStack(alignment: .leading, spacing: 0) {
            if hidden > 0 {
                WorkEarlierSteps(count: hidden, open: onShowEarlier)
            }
            ForEach(steps[hidden...]) { step in
                WorkStepView(
                    step: step,
                    rail: WorkRailPosition(
                        above: step.id != steps[hidden].id || hidden > 0,
                        below: step.id != steps.last?.id),
                    isLive: isLiveTail && step.id == steps.last?.id,
                    highlighted: highlightedSeq.map { step.covers($0) } ?? false,
                    findHit: findTarget.map { step.covers($0) } ?? false,
                    onOpenFile: onOpenFile
                )
                .equatable()
            }
        }
    }
}
#endif
