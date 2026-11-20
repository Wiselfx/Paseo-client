#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import Synchronization
import UIKit
import UniformTypeIdentifiers

// MARK: - Turn action availability

/// What the open agent can actually do with a turn. One value, computed once per agent/host
/// capability change by `ChatController` and passed to rows (R-2), so a provider that cannot
/// rewind or fork never shows an action that would fail.
///
/// Upstream's conditions:
/// - **Rewind** (`use-rewind-capabilities.ts:32-56`, `message.tsx:531`): the agent's
///   `capabilities.supportsRewind*` flags, under the host's `features.rewind`. Our
///   `rewindMenuScopes` is exactly that list.
/// - **Edit / Rerun** (`composer-restore.tsx`): rewind to the conversation, then restore the
///   text. Offered when the conversation scope can be rewound.
/// - **Fork** (`use-fork-agent.ts`: `useHostFeature(serverId, "agentForkContext")`): the host
///   feature and a shell that can open the new agent. A completed turn pins a boundary
///   (`turn-boundary.ts:9-24`), which needs `features.agentForkContextCursor` — the only
///   boundary this client sends (`ForkContextRequest.boundaryCursor`). The running turn forks
///   with no boundary and needs neither.
/// Upstream has no Retract or Delete-turn gesture; both were forks that spawned a new agent and
/// were removed (L1, LEDGER D-012). Rewind is the in-place path.
struct TurnActionAvailability: Sendable, Equatable {
    /// Scopes the provider offers on your bubbles, in menu order; empty hides rewind.
    var rewindChoices: [RewindScope] = []
    /// Fork with no boundary: the running turn's footer (`turn-footer.tsx:38-46`).
    var canForkInFlight = false
    /// Fork pinned to a boundary: the completed turn's footer.
    var canForkAtBoundary = false
    /// The workspace target is offered beside the tab target: the host can create one.
    var canForkWorkspace = false
    /// A rewind is in flight: the rewind items are locked until it settles (upstream
    /// `rewind-menu.tsx` `isLocked`).
    var rewindInFlight = false
}
#endif
