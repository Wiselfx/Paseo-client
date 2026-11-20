#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

struct ClaudeSearchResults: View {
    let search: ToolCallDetail.Search


    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let results = search.webResults, !results.isEmpty {
                ForEach(results, id: \.url) { result in
                    if let url = URL(string: result.url) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.paseo(.callout, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(2)
                                Text(url.host() ?? result.url)
                                    .font(.paseo(.footnote))
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    }
                }
            } else if let files = search.filePaths, !files.isEmpty {
                ClaudeCodeBlock(output: files.joined(separator: "\n"))
            } else if let content = search.content, !content.isEmpty {
                ClaudeCodeBlock(output: content)
            } else {
                Text("No results").font(.paseo(.footnote)).foregroundStyle(Palette.tertiaryInk)
            }
        }
    }
}
#endif
