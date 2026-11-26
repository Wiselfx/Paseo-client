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

    func report(_ seqEnd: Int, _ frame: CGRect) { frames[seqEnd] = frame }
    func frame(of seqEnd: Int) -> CGRect? { frames[seqEnd] }
    func reset() { frames.removeAll() }
}
#endif
