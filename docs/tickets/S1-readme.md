# S1: rewrite README.md

Read `AGENTS.md` first. You own only `README.md` (and a new `docs/images/` folder is NOT needed: use placeholders).

## What to write
A short README that presents this repo as **a native SwiftUI client for Paseo**, in the way Paseo's own README presents itself:
plain, calm, specific. Read upstream's README first for tone and structure only (`/home/paseo/dev/paseo-upstream-ref/README.md`); do not copy its
wording or claims.

Rules, from the owner:
- Less is more. Simple and elegant. State what it is, for what it is.
- No marketing language, no AI-sounding prose, no hype words, no claims you cannot back from the repo.
- Do not overclaim and do not underclaim. Do not write a "limitations", "drawbacks", "known issues" or "disclaimer" section.
  Facts about requirements are fine (it connects to a Paseo daemon you run; iPhone; iOS version from `App/project.yml`).
- Image placeholders: where a screenshot belongs, put a clearly marked placeholder line such as
  `<!-- screenshot: chat -->` plus a markdown image to a path that does not exist yet (for example `docs/images/chat.png`) with alt text.
  Two or three placeholders at most (chat, sidebar and workspaces, workspace panel).
- The repo is public: no hostnames, addresses, tokens, personal names, real agent titles, or private paths.

## Facts (verify every one against the repo before you write it)
- What the app does: read `docs/PARITY.md` (the "Counts" section and the area headings) and `docs/STATUS.md` (top), then check the code
  (`Packages/PaseoUI/Sources/PaseoUI`, `App/Sources`, `App/project.yml`) for what is actually reachable. Only name features you confirmed exist.
- Layout section: list only folders that exist (`Packages/PaseoCore`, `Packages/PaseoUI`, `App/`, `Tools/`, `docs/`). The current README mentions
  `Packages/ClaudeUI`; check if it exists and drop it if not.
- Build and test: the commands that really work (`swift test` in `Packages/PaseoCore` on Linux; the Xcode project in `App/`, generated from
  `App/project.yml` with XcodeGen: check how the repo says to build). Keep it to a few lines.
- Links: keep `ARCHITECTURE.md`, `AGENTS.md`, `docs/`. Link upstream Paseo (https://github.com/getpaseo/paseo).
- License: read `LICENSE` and name it correctly.

## Style pass (one time, not an install)
After drafting, apply the humanizer checklist to your own draft. The full text is at
`/tmp/claude-0/-home-paseo-dev-Paseo-client/9858bb74-4e7b-4b2f-b312-cccf25f9520c/scratchpad/humanizer-SKILL.md`. Read it once, find the patterns in your text
(staging instead of stating, forced triads, em-dash habit, inflated wording, decorative bold or emoji, vague claims), and rewrite until none remain.
Keep every fact. Do not install or copy that file into the repo.

## Done
Commit `S1: README` on your branch (never push or merge). Final message: the README text as committed, which facts you verified and where, and anything
you removed because you could not confirm it.
