export const meta = {
  name: 'measure-then-fix',
  description: 'Fix a feel/perf bug by measuring it: audit the code, build a CI simulator harness that puts numbers on it, verify the harness, then test a fix against the numbers',
  whenToUse: 'A UI bug that static reasoning has failed to fix (jank, jumps, layout drift, hitches, slow screens). Pass args: {problem, slug, scope, audits?, fix?}.',
  phases: [
    { title: 'Understand', detail: 'parallel read-only audits, file:line evidence, ranked mechanisms' },
    { title: 'Harness', detail: 'build a deterministic simulator harness + CI job on harness/<slug>, iterate until green with a baseline report' },
    { title: 'Verify', detail: 'skeptic checks the harness drives real code and its metrics are not vacuous' },
    { title: 'Fix', detail: 'optional: candidate fix on harness/<slug>-fix, compared against the baseline' },
  ],
}

// Proven on the transcript scroll jank (2026-11-26): three guessed rewrites failed on device; the
// harness showed the cause in one run (cells taking their safe area) and proved the fix (678 -> 0).
//
// args = {
//   problem: 'what the user sees, in their words',
//   slug:    'short-kebab-name',            // branches harness/<slug>, harness/<slug>-fix
//   scope:   'Packages/PaseoUI/Sources/...', // where the code lives
//   audits:  [{ key, prompt }],              // optional; default: mechanisms + timing
//   fix:     true,                           // optional; run the fix phase
// }

const ROOT = '/home/paseo/dev/Paseo-client'
const A = args || {}
const PROBLEM = A.problem || 'unspecified: ask for args.problem'
const SLUG = A.slug || 'bug'
const SCOPE = A.scope || 'Packages/PaseoUI/Sources/PaseoUI'

const CONTEXT = `Repo ${ROOT}. iOS app, SwiftUI + UIKit, iOS 26 target, Swift 6 strict concurrency. NO local Swift toolchain (Linux): GitHub Actions CI (runner xcode-27) is the only compiler and test runner; use the gh CLI. The existing harness pattern to copy: Packages/PaseoUI/Tests/PaseoUITests/TranscriptHarnessTests.swift + Harness/*.swift and .github/workflows/transcript-harness.yml (hosts real views in a UIWindow with a fake DaemonClient and synthetic data from production decoding, writes report.md/report.json to TRANSCRIPT_HARNESS_OUT, artifact upload, runs on push to harness/**). Follow the swiftui-pro skill (${ROOT}/.claude/skills/swiftui-pro/SKILL.md) for any SwiftUI.

THE PROBLEM (user's words): ${PROBLEM}
CODE SCOPE: ${SCOPE}`

const AUDITS = A.audits || [
  { key: 'mechanisms', prompt: 'List every mechanism in the scope that could produce the problem (state changes after appear, measure vs draw differences, environment/safe-area/trait inputs, async swaps, animations on a second clock, programmatic offset or frame writes). Rank them.' },
  { key: 'timing', prompt: 'Trace the runtime sequence when the problem happens: which callbacks, layout passes, Task hops and invalidations run, in what order, and every place that writes geometry. Mark what depends on UIKit/SwiftUI runtime behaviour as UNVERIFIED.' },
]

phase('Understand')
const audits = await parallel(AUDITS.map(a => () => agent(
  `${CONTEXT}\n\nREAD-ONLY AUDIT (${a.key}). Do not modify, build or commit anything. ${a.prompt}\nCite file:line for every claim; mark anything not visible in source as UNVERIFIED. End with: what a harness must log or measure to confirm or kill each ranked item.`,
  { label: `audit:${a.key}`, phase: 'Understand', model: 'haiku', effort: 'max' })))
const auditText = audits.filter(Boolean).map((r, i) => `### ${AUDITS[i].key}\n${r}`).join('\n\n')

phase('Harness')
const built = await agent(
  `${CONTEXT}\n\nAUDITS (hypotheses, not facts):\n${auditText}\n\nBuild a deterministic simulator harness that MEASURES the problem in the real production code, on branch harness/${SLUG} (from main; never push to main). Host the real views as production composes them (same SwiftUI insets/bars/containers, window from a connected scene when there is one). Drive the interaction in small steps with the run loop spun between steps. Record per step what the user would see move (screen-space positions of drawn content, not just frames), plus every invalidation/geometry write with its cause. Add only inert hooks to production (a static optional sink, nil in production). Write report.md (totals per scenario, top 20 worst events with context) and report.json. The test never fails on the bug, only on harness errors. Add a CI workflow (copy transcript-harness.yml) triggered on harness/** and workflow_dispatch. Push, watch with gh run watch, fix failures (gh run view --log-failed), up to ~12 iterations. Commit messages end with: Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>. Return: branch, sha, run URL, report.md content, how each metric is measured, limitations.`,
  { label: 'build-harness', phase: 'Harness', model: 'sonnet', effort: 'high' })

phase('Verify')
const verdict = await agent(
  `${CONTEXT}\n\nYou are a skeptical reviewer of a measurement harness on branch harness/${SLUG} (git fetch; read with git show origin/harness/${SLUG}:<path>; do not modify or push). Builder summary:\n${built}\n\nCheck with file:line evidence: (1) it drives the real production code composed as in the app (compare against the real screen; any emulated input that production never sets is High); (2) each metric's math, sign, and whether it can miss real events or report false ones; (3) whether any metric is vacuous (always equal by construction); (4) which production branches the simulated interaction does not reach; (5) hooks inert, no behaviour change in git diff origin/main...origin/harness/${SLUG}; (6) baseline numbers that look implausible, double counted or misattributed. Return verdict (valid / valid-with-gaps / invalid), gaps by severity with exact fixes, and the mechanism the data actually supports.`,
  { label: 'verify-harness', phase: 'Verify', model: 'haiku', effort: 'max' })

let fix = null
if (A.fix) {
  phase('Fix')
  fix = await agent(
    `${CONTEXT}\n\nHarness summary:\n${built}\n\nReviewer verdict:\n${verdict}\n\nFirst fix any High harness gap on harness/${SLUG} and re-run to get a trustworthy baseline. Then branch harness/${SLUG}-fix from it, make the smallest fix the DATA supports (not the audits' guesses), push, and compare its report to the baseline metric by metric. If a metric does not improve, say so and iterate (up to ~6 runs); do not merge to main. Commit messages end with: Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>. Return: the fix diff summary, before/after table, residual events and what they are, run URLs.`,
    { label: 'fix-candidate', phase: 'Fix', model: 'sonnet', effort: 'high' })
}

return { audits: auditText, built, verdict, fix }
