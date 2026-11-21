#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A GitHub PR, issue, commit or run link: the row card with a `StatePill`, or the
/// live checkout-PR card when the number matches the workspace's PR.
struct RichGitHubCard: View {
    let url: String
    let parsed: GitHubURL

    @Environment(\.richActions) private var richActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSafari = false
    @State private var info: GitHubLinkInfo?
    @State private var lookedUp = false

    /// The checkout's PR, mirrored by the conversation controller. Nil outside one.
    private var checkoutPR: CheckoutPrStatus? { richActions?.checkoutPR }

    /// The workspace's PR when this link points at it (number match; repo match when
    /// both sides name one). That card is live (C13); everything else is a snapshot.
    private var matchedPR: CheckoutPrStatus? {
        guard case .pull(let number) = parsed.kind,
            let pr = checkoutPR, pr.number == number
        else { return nil }
        if let owner = pr.repoOwner, let name = pr.repoName,
            owner.lowercased() != parsed.owner.lowercased()
                || name.lowercased() != parsed.repo.lowercased()
        {
            return nil
        }
        return pr
    }

    private var linkTitle: String {
        if let info { return info.title }
        return "\(parsed.slug)\(kindSuffix)"
    }

    private var kindSuffix: String {
        switch parsed.kind {
        case .repo: ""
        case .pull(let n): " #\(n)"
        case .issue(let n): " #\(n)"
        case .commit(let sha): " @\(String(sha.prefix(7)))"
        case .actionsRun(let id): " run \(id)"
        }
    }

    private var linkMeta: String {
        "github.com · \(parsed.slug)\(kindSuffix)"
    }

    private var glyph: String {
        switch parsed.kind {
        case .pull: "arrow.branch"
        case .issue: "circle"
        case .commit: "number"
        case .actionsRun: "play.circle"
        case .repo: "folder"
        }
    }

    /// The row shape from the first frame: a GitHub URL never shows the generic
    /// hero link card. The title and state fill in in place (same height) when the
    /// lookup lands; the live PR card grows once, animated, when it can be known.
    var body: some View {
        Group {
            if let matchedPR {
                GitHubPRCard(pr: matchedPR, url: url, onOpen: openPRPane)
            } else if let info {
                GitHubLinkRow(
                    glyph: glyph, title: info.title, slug: parsed.slug, state: info.state,
                    url: url, onOpen: openSafari)
            } else {
                // Before the lookup answers: slug, kind and glyph, no state yet.
                GitHubLinkRow(
                    glyph: glyph, title: "\(parsed.slug)\(kindSuffix)", slug: parsed.slug,
                    state: nil, url: url, onOpen: openSafari)
            }
        }
        .task(id: lookupKey) { await lookup() }
        .animation(
            Motion.disclosure.resolved(reduceMotion: reduceMotion), value: cardShape)
        // Attached above the branches: a lookup landing (or the checkout PR arriving) while
        // Safari is up swaps the row for another view, and a cover hosted by the swapped-out
        // row would be dismissed from under the reader.
        .fullScreenCover(isPresented: $showSafari) {
            if let target = URL(string: url) {
                SafariView(url: target).ignoresSafeArea()
            }
        }
    }

    /// What the card is showing, as one value, so the taller live PR card grows
    /// once (animated) instead of swapping heights under the reader.
    private var cardShape: Int {
        if matchedPR != nil { return 2 }
        if info != nil { return 1 }
        return 0
    }

    /// One lookup per URL, through the controller's forge search — same repo only, and
    /// only when the checkout names its repo. Anything else degrades to the link card
    /// (a workspace-scoped search must never answer for a foreign repo).
    private var lookupKey: String? {
        guard matchedPR == nil, !lookedUp, sameRepo == true else { return nil }
        return url
    }

    /// Whether the link names the checkout's repo. Nil when the checkout names none:
    /// without a repo to match against, the card stays a link card.
    private var sameRepo: Bool? {
        guard let pr = checkoutPR, let owner = pr.repoOwner, let name = pr.repoName else {
            return nil
        }
        return owner.lowercased() == parsed.owner.lowercased()
            && name.lowercased() == parsed.repo.lowercased()
    }

    // MARK: Resolution

    @MainActor
    private func lookup() async {
        lookedUp = true
        // Same repo only, and only when the checkout names its repo: a
        // workspace-scoped search must never answer for a foreign repo.
        guard sameRepo == true, let lookup = richActions?.githubLookup else { return }
        guard let found = await lookup(parsed) else { return }
        guard !Task.isCancelled else { return }
        info = found
    }

    private func openPRPane() {
        richActions?.openPRPane()
    }

    private func openSafari() {
        showSafari = true
    }
}
#endif
