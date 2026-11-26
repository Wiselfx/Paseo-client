#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Row frames

/// Where each timeline row sits inside its turn's cell (`rowAnchor`). A row reports its frame in the
/// cell's own coordinate space, which does not move while the transcript scrolls, so reporting costs
/// nothing per scroll frame. A jump to a row adds it to the cell's frame in the layout.
@MainActor
final class TranscriptRowFrames {
    nonisolated static let space = "paseo.transcript.cell"
    private var frames: [Int: CGRect] = [:]

    /// Set by the engine while it follows a row through a resize; called once per main-actor turn after
    /// reports that moved a row, and never while nil (streaming reports cost nothing).
    var onChange: (@MainActor () -> Void)?
    private var notifyScheduled = false

    func report(_ seqEnd: Int, _ frame: CGRect) {
        let previous = frames[seqEnd]
        frames[seqEnd] = frame
        guard previous != frame, onChange != nil, !notifyScheduled else { return }
        notifyScheduled = true
        Task { [weak self] in
            guard let self else { return }
            self.notifyScheduled = false
            self.onChange?()
        }
    }
    func frame(of seqEnd: Int) -> CGRect? { frames[seqEnd] }
    func reset() { frames.removeAll() }
    /// Drops the frames of rows whose cell is coming back on screen: they describe its last visit.
    func forget(_ seqs: [Int]) {
        for seq in seqs { frames[seq] = nil }
    }
}
#endif
