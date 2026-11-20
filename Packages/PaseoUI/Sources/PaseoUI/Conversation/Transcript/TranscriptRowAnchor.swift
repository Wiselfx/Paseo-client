#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Reports a row's frame inside its cell for every `seqEnd` it stands for.
struct TranscriptRowAnchor: ViewModifier {
    let seqs: [Int]
    @Environment(\.transcriptRowFrames) private var frames

    /// The frame and the rows it stands for: a view that takes over rows (a work section folding
    /// its steps away) reports again even when its own frame did not move.
    private struct Report: Equatable {
        var frame: CGRect
        var seqs: [Int]
    }

    func body(content: Content) -> some View {
        let sink = frames
        let seqs = seqs
        content.onGeometryChange(for: Report.self) { proxy in
            Report(frame: proxy.frame(in: .named(TranscriptRowFrames.space)), seqs: seqs)
        } action: { report in
            guard let sink else { return }
            for seq in report.seqs { sink.report(seq, report.frame) }
        }
    }
}
#endif
