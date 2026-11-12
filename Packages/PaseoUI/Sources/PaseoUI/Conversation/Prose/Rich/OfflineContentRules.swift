#if canImport(UIKit)
import Foundation
import WebKit

// MARK: - OfflineContentRules (G4/G5 hardening)

// NOTE: RemoteImagePipeline/G4: the second layer under the documents' own offline CSP.
// Chat artifacts (visualize fences, html fences, raw SVG, mermaid host) must not reach
// the network no matter what markup an agent wrote: a `WKContentRuleList` on the web
// view blocks http(s)/ws(s) subresources and navigations at the WebKit level. The Files
// panel and file artifact pages keep today's behaviour (no rule list) because workspace
// files legitimately load CDN subresources through the scheme handler.

/// One compiled rule list, shared by every chat web view. Compiled once, off the
/// critical path; callers `await` it before their first load and otherwise render as
/// before (their CSP already covers the gap while it compiles).
@MainActor
enum OfflineContentRules {
    private static var cached: WKContentRuleList?
    private static var compileTask: Task<WKContentRuleList?, Never>?

    static func list() async -> WKContentRuleList? {
        if let cached { return cached }
        if let compileTask { return await compileTask.value }
        let task = Task.detached(priority: .utility) { () -> WKContentRuleList? in
            let store = WKContentRuleListStore.default()
            return try? await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<WKContentRuleList?, Error>) in
                store.compileContentRuleList(
                    forIdentifier: "paseo-offline-chat",
                    encodedContentRuleList: OfflineContentRules.json
                ) { list, _ in
                    continuation.resume(returning: list)
                }
            }
        }
        compileTask = task
        let list = await task.value
        compileTask = nil
        if let list { cached = list }
        return list
    }

    /// Block every http(s)/ws(s) load, all resource kinds. `data:`/`blob:` (inline
    /// pixels) and `file:` (never loaded here) are unaffected.
    static let json = """
        [
          {"trigger": {"url-filter": "^https?://", "resource-type": ["document", "image", "style-sheet", "script", "font", "raw", "svg-document", "media", "popup"]}, "action": {"type": "block"}},
          {"trigger": {"url-filter": "^wss?://", "resource-type": ["document", "raw"]}, "action": {"type": "block"}}
        ]
        """
}
#endif
