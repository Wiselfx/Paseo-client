#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Thinking

/// The whole thought: paragraphs in the serif, the model's own emphasis kept (its section titles
/// arrive in bold), selectable.
struct WorkThoughtText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.paragraphs(text).enumerated(), id: \.offset) { _, paragraph in
                Text(Self.styled(paragraph))
                    .font(.paseo(.processTitle))
                    .lineSpacing(5)
                    .foregroundStyle(Palette.secondaryInk)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    static func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// A paragraph's inline Markdown (the model's `**titles**`), parsed once per paragraph.
    static func styled(_ paragraph: String) -> AttributedString {
        if let cached = styledCache.value(for: paragraph) { return cached }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        let styled =
            (try? AttributedString(markdown: paragraph, options: options)) ?? AttributedString(paragraph)
        styledCache.setValue(styled, for: paragraph)
        return styled
    }

    private static let styledCache = ProseCache<String, AttributedString>(
        budget: 2 * 1024 * 1024, countLimit: 512, cost: { key, _ in key.utf8.count * 3 })
}
#endif
