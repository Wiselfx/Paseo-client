#!/usr/bin/env bash
# repeat.sh: the measurement rule (PERFORMANCE-RULES.md): one scenario, N cold-launch runs, median and
# range of the VERDICT numbers. Same chat, same script, app-start window excluded (perf-run waits 8 s
# after launch before it stamps the start), same window length. Run the idle floor ("idle" "wait 12") on
# the same build and read every other number against it.
#   GATE_HOST=<login> repeat.sh <name> "<do steps>" [runs=3]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
name="$1"; steps="$2"; runs="${3:-3}"
for i in $(seq 1 "$runs"); do
  "$here/perf-run.sh" "$name" "$steps" | grep '^VERDICT' | sed "s/^/run$i /"
done | python3 -c '
import sys,re,statistics as st
rows=[dict(re.findall(r"(\S+)=(\S+)",l)) for l in sys.stdin]
def num(k): return [float(r[k].rstrip("ms%")) for r in rows]
out=[]
for k in ("hitches","dropped","worst-frame","stalls>8ms","stall-max","busy-avg"):
    v=num(k); out.append("%s med %.1f [%.1f..%.1f]"%(k,st.median(v),min(v),max(v)))
print(sys.argv[1], "runs=%d"%len(rows), " | ".join(out))' "$name"
