#if canImport(UIKit)
import Foundation

/// Forge-search answers for same-repo GitHub links, by URL. A card that remounts (scrolling
/// back, a re-rendered row) reads its title and state on the first pass instead of searching
/// again. Entries expire, because a PR's state changes; the oldest entry goes at the limit.
@MainActor
enum RichGitHubLookupCache {
    private static let limit = 64
    private static let lifetime: TimeInterval = 300
    private static var table: [String: (info: GitHubLinkInfo, at: Date)] = [:]
    /// Insertion order, oldest first, for eviction.
    private static var order: [String] = []

    static func info(for url: String) -> GitHubLinkInfo? {
        guard let entry = table[url], Date.now.timeIntervalSince(entry.at) < lifetime else {
            return nil
        }
        return entry.info
    }

    static func store(_ info: GitHubLinkInfo, for url: String) {
        if table[url] != nil {
            order.removeAll { $0 == url }
        } else if table.count >= limit, let oldest = order.first {
            order.removeFirst()
            table[oldest] = nil
        }
        order.append(url)
        table[url] = (info: info, at: Date.now)
    }
}
#endif
