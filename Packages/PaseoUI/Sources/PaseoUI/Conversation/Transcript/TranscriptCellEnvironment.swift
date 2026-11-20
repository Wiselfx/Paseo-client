#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// What every cell needs from the SwiftUI side. A cell is hosted outside the screen's SwiftUI tree, so
/// the environment the turns read is handed over explicitly.
struct TranscriptCellEnvironment {
    var store: ConversationStore
    var controller: ChatController
    var history: HistoryStartController
    weak var engine: TranscriptEngine?
    var ui: TranscriptUIState
    var rowFrames: TranscriptRowFrames
    var openURL: OpenURLAction
    /// The prose column (the transcript's width less its margins).
    var column: CGFloat
    /// The keyboard-independent viewport height: media caps and the process cap read it.
    var viewport: CGFloat
    var toast: ToastCenter?
    var shellDrawer: ShellDrawer?
    var surfaceFlags: SurfaceFlags?
    var codeSizeStep: Int
    var artifactZoom: Namespace.ID?
    var dynamicType: String

    /// Something every cell draws changed: visible cells are configured again.
    func needsReconfigure(from old: TranscriptCellEnvironment?) -> Bool {
        guard let old else { return true }
        return abs(column - old.column) > 0.5 || abs(viewport - old.viewport) > 0.5
            || codeSizeStep != old.codeSizeStep || toast !== old.toast
            || shellDrawer !== old.shellDrawer || surfaceFlags !== old.surfaceFlags
            || artifactZoom != old.artifactZoom || dynamicType != old.dynamicType
    }
}
#endif
