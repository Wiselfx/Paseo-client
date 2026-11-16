# Picking this project up in a fresh Linux container

Everything the code needs is in this repo (`foundation` and `main` are the same commit). What is not in git:

1. **Toolchain (Linux, for PaseoCore tests).** Install swiftly, then Swift 6.4.x:
   `. ~/.local/share/swiftly/env.sh; cd Packages/PaseoCore; swift build --build-tests && swift test`.
   `Packages/PaseoUI` and `App/` only compile on a Mac.
2. **The Mac build gate.** `Tools/build-gate/build-gate` is the forced-command script (its header lists every verb). It is installed
   on the Mac by hand; the Linux side needs the SSH key authorised for it. Keep the key and the host name out of the repo.
   The gate builds from GitHub, so push a branch before asking it to build.
3. **Upstream reference (read-only).** `git clone https://github.com/getpaseo/paseo.git` next to this repo. Rule R-7 in `AGENTS.md` makes
   it the specification.
4. **A test daemon** for streaming checks (`paseo` CLI, pi provider only, never a claude-provider agent): see `docs/perf/HOWTO.md`.
5. **Rules and history.** `AGENTS.md`, `ARCHITECTURE.md`, `Performance/` (binding; run `Performance/scripts/final-check.sh <base>`),
   `docs/STATUS.md`, `docs/perf/` (raw measurements), `docs/tickets/`.

Local-only scratch branches (`ocu-ui`, `t16-flake-usage`, `w1-baseline`, `w1-scratch-rowid`, `merge-check`) were never merged and are
experiments; nothing the app needs is on them.
