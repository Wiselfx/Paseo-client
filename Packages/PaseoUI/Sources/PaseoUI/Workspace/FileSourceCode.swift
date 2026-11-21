#if canImport(UIKit)
import SwiftUI

/// Source view without another decode: reuses the highlighted model when it is this text.
struct FileSourceCode: View {
    let text: String
    let render: FileRenderModel?

    var body: some View {
        if let render, case .text(let modelText, let highlighted, let lines) = render.payload,
            modelText == text
        {
            WorkspaceCodeView(text: modelText, highlighted: highlighted, lines: lines).equatable()
        } else {
            WorkspaceCodeView(text: text, highlighted: nil, lines: text.splitLines())
        }
    }
}
#endif
