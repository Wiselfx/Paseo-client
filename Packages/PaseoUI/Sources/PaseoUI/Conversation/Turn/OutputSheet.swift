#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The full-output sheet behind "Show all N lines": an optional cap note and "Copy all" row above
/// the text, which scrolls both ways. Shared by the plain preview (a `String` head) and the
/// terminal block (an ANSI-coloured `AttributedString`), so each passes its own `Text`.
struct OutputSheet: View {
    /// "Showing the first/last N of M lines", when the output is longer than the sheet's cap.
    let note: Text?
    /// The whole output for "Copy all", read only when tapped. Nil leaves the button out.
    let copyAll: (() -> String)?
    let content: Text

    var body: some View {
        SheetScaffold("Output", detents: .large) {
            VStack(alignment: .leading, spacing: 0) {
                if note != nil || copyAll != nil {
                    HStack {
                        if let note {
                            note
                                .font(.paseo(.caption))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        Spacer(minLength: Space.sm)
                        if let copyAll {
                            ClaudeCopyButton(text: copyAll(), label: "Copy all")
                        }
                    }
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                }
                ScrollView([.vertical, .horizontal]) {
                    content
                        .font(.paseo(.codeSmall))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(Space.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
#endif
