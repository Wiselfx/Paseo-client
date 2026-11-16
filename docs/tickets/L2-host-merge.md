# L2 — One host per daemon: relay and direct connections merge (upstream model), best-connection selection

Read `_L-common.md` first. Branch: `l2-hosts`. Commit messages start with `L2:`.
Findings: `/home/paseo/dev/docs-audit/findings/LEDGER-EXTRA.md` X-004; `REVIEW.md`.
Decision (product owner, final): **match upstream**. Upstream doc: `public-docs/connectivity.md:127`
("If the host was already paired through the relay, Paseo adds the direct connection to the same host").

## What upstream does (read these first, in full)
- `packages/app/src/types/host-connection.ts` — a `HostProfile` is keyed by the daemon `serverId` and has
  `connections: HostConnection[]` (types `directTcp`, `relay`, …) and `preferredConnectionId`.
- `packages/app/src/runtime/host-runtime.ts`: `upsertDirectConnection` (~line 2017) and
  `upsertHostConnection` (see how a connection is added to an existing profile with the same `serverId`
  instead of creating a second host); the relay equivalent (grep `upsertRelayConnection`).
- `packages/app/src/utils/connection-selection.ts` — `selectBestConnection`: of the connections whose probe
  says `available`, pick the lowest latency; none → null.
- `packages/app/src/runtime/host-runtime.ts` ~lines 1060-1130 — the adaptive switch rule
  (`ADAPTIVE_SWITCH_THRESHOLD_MS`, `ADAPTIVE_SWITCH_CONSECUTIVE_PROBES`): switch the active connection only
  when another one is faster by the threshold for N consecutive probes. Find the two constants with grep.

## You own
`Packages/PaseoCore/Sources/PaseoKit/SavedHost.swift`, new files in `Packages/PaseoCore/Sources/PaseoKit/`
and `Packages/PaseoCore/Sources/PaseoStore/` for the pure logic, tests in `Packages/PaseoCore/Tests/`, and
`App/Sources/SavedHosts.swift` (the Keychain-backed list). Do NOT edit any PaseoUI screen file; list the
screens that need changes under "Found, not fixed".

## Part A — pure selection logic (PaseoStore, Linux-tested)
1. Create `Packages/PaseoCore/Sources/PaseoStore/ConnectionSelection.swift` with a Swift port of
   `selectBestConnection` and the adaptive switch decision (inputs: candidates, probe states
   `pending|unavailable|available(latencyMs)`, active connection id + its RTT, current candidate streak;
   output: the connection to switch to or none). Use the upstream constants' values (grep them).
2. Tests in a NEW file `Packages/PaseoCore/Tests/PaseoStoreTests/ConnectionSelectionTests.swift`: copy the
   cases from upstream's `connection-selection` tests if they exist
   (`find /home/paseo/dev/paseo-upstream-ref/packages/app -name "*connection-selection*"`), plus: no
   candidates → none; all unavailable → none; lowest latency wins; ties keep the first; below the threshold
   no switch; streak resets when the fastest changes.

## Part B — merge on discovery (PaseoKit + App adapter)
Today `SavedHost` is one row per connection (`identityKey` = `relay:<serverID>` or the URL;
`SavedHost.swift:57-66`) and `SavedHostDuplicates` only detects duplicates. Make it the upstream shape with
the smallest change that keeps old saved data decoding (the existing migration tests must still pass):
1. Add to `SavedHost` an optional `directURL: String?` and `directUseTLS`-free (the `ws(s)` scheme in the URL
   carries TLS) — the alternate direct endpoint of a **relay** row — and make the type decode old blobs
   without it (tolerant decode, like the existing fields). A relay row with `directURL != nil` has two
   connections: relay and direct.
2. Add `SavedHost.connections` (computed, not stored): the list of `(id, kind, endpoint)` — `relay:<serverID>`
   and `direct:<normalized endpoint>` — matching upstream's connection ids (`direct:${endpoint}`).
3. Add a pure function `SavedHostMerge.merge(direct: SavedHost, into relay: SavedHost) -> SavedHost`:
   the relay row wins (its `id`, `serverID`, key, label if the user renamed it); it gains
   `directURL = direct.url`; `lastConnectedAt` = the later of the two. Keychain rule: the direct row's
   password is moved to the relay row's account only if the relay row has none; never overwrite a password.
4. Add `SavedHostDuplicates.mergePlan(_ hosts: [SavedHost]) -> [(keep: SavedHost, absorb: SavedHost)]`
   for each group where one is a relay row and the other a direct row of the same `daemonServerID`
   (two direct rows or two relay rows for one daemon: not merged, unchanged behaviour).
5. In `App/Sources/SavedHosts.swift`: where a direct host learns its `serverId`
   (`learnDirectServerID`), if the id matches a relay row, apply the merge plan: update the relay row, move the
   password per rule 3 through the same Keychain adapter used elsewhere in that file, delete the direct row,
   and keep the active-host selection pointing at the merged row. If the user pairs a relay offer whose
   `serverID` matches an existing direct row's `directServerID`, do the reverse merge into the new relay row.
   Reuse the file's existing persistence/Keychain functions; add none.
6. Tests (NEW files in `Packages/PaseoCore/Tests/PaseoKitTests/`): merge keeps relay identity; password
   rule (relay has none / relay has one); old blobs decode; `connections` ids match the upstream scheme;
   two directs for one daemon are untouched.

## Not in this ticket (list as follow-up in your final message)
Probing all connections and switching at runtime (needs `DaemonConnection` changes: another worker's
files); the Settings/host-picker rows showing "2 connections". State exactly which functions they must call
(your `ConnectionSelection` API).

## Proof
`swift build --build-tests` clean in your files, `swift test` passes; paste the counts. `swiftc -parse`
`App/Sources/SavedHosts.swift`; list any Apple API you were not sure of.
