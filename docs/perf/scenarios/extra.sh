#!/usr/bin/env bash
# extra.sh: scenarios 3 to 5 and the rich-media variants, scripted. Run with the rich-media test chat
# open (Search, type its title, tap the result) and the app launched with -paseo-perf.
#   3 prose / dynamic type   4 code blocks   5 think and work groups   7b link, video, audio cards
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
key="${GATE_KEY:-/home/paseo/.ssh/paseo_build_ed25519}"; host="${GATE_HOST:-claude@host.orb.internal}"
g() { ssh -i "$key" -o BatchMode=yes "$host" "$@" >/dev/null; }
scroll="scroll down | scroll down | scroll down | scroll down | scroll down | scroll down | scroll up | scroll up | scroll up | scroll up | scroll up | scroll up | wait 1"
for size in ax5 xs m; do g "textsize $size"; g "do wait 3"; "$here/perf-run.sh" --keep "3-prose-textsize-$size" "$scroll" | tail -1; done
for mode in light dark; do g "appearance $mode"; g "do wait 2"; "$here/perf-run.sh" --keep "3-prose-$mode" "$scroll" | tail -1; done
"$here/perf-run.sh" --keep 4-code-expand-collapse "tap Expand code | wait 2 | tap Close code | wait 2 | tap Copy code | wait 1" | tail -1
"$here/perf-run.sh" --keep 4-code-horizontal "swipe 360 700 60 700 | wait 1 | swipe 60 700 360 700 | wait 1" | tail -1
"$here/perf-run.sh" --keep 5-work-group-toggle "tap Completed in 7s | wait 2 | tap Completed in 7s | wait 2" | tail -1
"$here/perf-run.sh" --keep 7b-media-cards "$scroll | scroll down | scroll down | scroll down | scroll down | wait 2" | tail -1
