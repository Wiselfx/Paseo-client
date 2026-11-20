#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// The sorted, filtered rows of one listing, remembered between passes. The page re-evaluates for
/// every `@State` it owns (the name prompt's text field writes one per keystroke); sorting hundreds of
/// entries with locale-aware compares on each of those passes was pure waste (R-1). Valid while the
/// entries, the hidden toggle and the sort key are what they were.
@MainActor final class FileListMemo {
    private var entries: [FileExplorerEntry]?
    private var showHidden = false
    private var sort = FileSort.name
    private var result: [FileExplorerEntry] = []

    func visible(
        _ entries: [FileExplorerEntry], showHidden: Bool, sort: FileSort,
        build: () -> [FileExplorerEntry]
    ) -> [FileExplorerEntry] {
        if let cached = self.entries, self.showHidden == showHidden, self.sort == sort,
            cached == entries
        {
            return result
        }
        let built = build()
        self.entries = entries
        self.showHidden = showHidden
        self.sort = sort
        result = built
        return built
    }
}
#endif
