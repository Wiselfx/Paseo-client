import Foundation

// MARK: - GitHubURL (G9 C7)

// NOTE: RemoteImagePipeline/G9: the link kind coding agents print most. A pure parser
// over the `.linkCard` URL: same-repo PRs that match the checkout become the live PR
// card (C13); same-repo siblings resolve through forge search; everything else falls
// back to the metadata link card.

/// A parsed `github.com` URL. Only the shapes coding agents actually emit.
public struct GitHubURL: Sendable, Equatable, Hashable {
    public var owner: String
    public var repo: String
    public var kind: Kind

    public enum Kind: Sendable, Equatable, Hashable {
        /// The repo root (possibly with a tree/blob suffix, which the card ignores).
        case repo
        case pull(number: Int)
        case issue(number: Int)
        case commit(sha: String)
        case actionsRun(id: String)
    }

    /// Parses `https://github.com/<owner>/<repo>(/pull/<n>|/issues/<n>|/commit/<sha>|
    /// /actions/runs/<id>|…)`. Query strings and fragments are ignored; anything without
    /// an owner and repo (or a non-GitHub host) yields nil and renders as a plain link.
    public static func parse(_ urlString: String) -> GitHubURL? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
            let host = url.host?.lowercased(),
            host == "github.com" || host == "www.github.com"
        else { return nil }
        // pathComponents keeps "/" entries; drop them.
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        let rest = Array(parts.dropFirst(2))
        if rest.isEmpty { return GitHubURL(owner: owner, repo: repo, kind: .repo) }
        switch rest[0].lowercased() {
        case "pull", "pulls":
            if rest.count >= 2, let number = Int(rest[1]) {
                return GitHubURL(owner: owner, repo: repo, kind: .pull(number: number))
            }
            return GitHubURL(owner: owner, repo: repo, kind: .repo)
        case "issues":
            if rest.count >= 2, let number = Int(rest[1]) {
                return GitHubURL(owner: owner, repo: repo, kind: .issue(number: number))
            }
            return GitHubURL(owner: owner, repo: repo, kind: .repo)
        case "commit":
            if rest.count >= 2, !rest[1].isEmpty {
                return GitHubURL(owner: owner, repo: repo, kind: .commit(sha: rest[1]))
            }
            return GitHubURL(owner: owner, repo: repo, kind: .repo)
        case "actions":
            if rest.count >= 3, rest[1].lowercased() == "runs", !rest[2].isEmpty {
                return GitHubURL(owner: owner, repo: repo, kind: .actionsRun(id: rest[2]))
            }
            return GitHubURL(owner: owner, repo: repo, kind: .repo)
        default:
            // tree/blob/releases/…: the repo card; the raw path adds no card value.
            return GitHubURL(owner: owner, repo: repo, kind: .repo)
        }
    }

    /// `owner/repo`, for same-repo matching against the checkout.
    public var slug: String { "\(owner)/\(repo)" }
}
