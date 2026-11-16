#!/usr/bin/env bash
# perf-run.sh: run one scripted scenario on the gate's simulator and print the app's `-paseo-perf`
# window lines plus a one-line verdict. See docs/perf/scenarios/README.md.
#
#   perf-run.sh [--keep] <name> "<do steps separated by |>"   (no --keep: relaunch with -paseo-perf first)
#
# Env: PERF_ARGS (launch arguments, comma-separated; default -paseo-perf; add -paseo-perf-sample for a
# profile, -paseo-perf-changes for SwiftUI's reasons), GATE_KEY (default /home/paseo/.ssh/paseo_build_ed25519), GATE_HOST (required, the gate login).
# The numbers come from the app itself (PerfMonitor); this script only drives and reads.
set -euo pipefail
key="${GATE_KEY:-/home/paseo/.ssh/paseo_build_ed25519}"
host="${GATE_HOST:?set GATE_HOST to the gate login, e.g. claude@<gate-host>}"
gate() { ssh -i "$key" -o BatchMode=yes "$host" "$@"; }

keep=0
if [ "${1:-}" = "--keep" ]; then keep=1; shift; fi
name="${1:?scenario name}"; steps="${2:?do steps}"

if [ "$keep" -eq 0 ]; then
  gate "launch ${PERF_ARGS:--paseo-perf}" >/dev/null
  gate "do wait 8" >/dev/null   # let the launch settle; its windows are not part of the scenario
fi
# The Mac's own clock (the shot name carries it) marks where the scenario starts, so windows printed
# before it (launch, an earlier scenario) are not counted.
stamp="$(gate "shot tm" | tail -1 | sed -E 's#.*/([0-9]{8})-([0-9]{6})-.*#\1 \2#')"
gate "do $steps" >/dev/null
gate "do wait 2" >/dev/null
lines="$(gate "applog 5" | grep 'perf\]' || true)"
log="$(printf '%s\n' "$lines" | python3 "$(dirname "$0")/summarize.py" --after "$stamp")"
echo "== $name"
printf '%s\n' "$log" | tail -n 70
