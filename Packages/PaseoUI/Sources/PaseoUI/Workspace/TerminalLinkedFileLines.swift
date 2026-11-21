#if canImport(UIKit)
import SwiftUI

/// A terminal-linked file's lines with a line-number gutter, the requested line centered and
/// highlighted.
struct TerminalLinkedFileLines: View {
    let lines: [String]
    /// The 1-based line the terminal link named.
    let targetLine: Int?

    private var digits: Int { max(2, String(max(lines.count, 1)).count) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.enumerated(), id: \.offset) { index, line in
                        let number = index + 1
                        HStack(spacing: 10) {
                            CodeLineNumber(
                                number: number, digits: digits, font: .paseo(.codeCaption))
                            Text(line)
                                .font(.paseo(.codeSmall))
                                .foregroundStyle(Palette.ink)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 1.5)
                        .background(
                            targetLine == number
                                ? Palette.chip
                                : Color.clear)
                        .id(number)
                    }
                }
                .padding(.vertical, 8)
                .textSelection(.enabled)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                if let targetLine, targetLine > 0 {
                    proxy.scrollTo(targetLine, anchor: .center)
                }
            }
        }
    }
}
#endif
