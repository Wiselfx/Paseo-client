#!/usr/bin/env bash
# stream.sh: scenario 2 (streaming). Sends a long markdown reply request to the long test chat
# (agent id in $AGENT, default the "Perf long" test agent) while the app shows that chat, and
# prints the perf windows. Needs the test daemon (PASEO_PASSWORD, port 6768) and a pi agent.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
agent="${AGENT:?set AGENT to the long test chat agent id}"
steps="${1:-wait 15 | wait 15 | wait 10}"
( sleep 3; PASEO_PASSWORD="${PASEO_PASSWORD:-simtest-pass}" paseo --host localhost:6768 send "$agent" \
  "Write a long detailed markdown guide of about 1500 words on making list scrolling smooth in mobile apps. Use several headings, bullet lists with inline code in many bullets, a table with 4 columns and 6 rows, and at least five fenced code blocks in different languages (swift, python, bash, json, typescript) of 15 to 30 lines each. No tools." >/dev/null 2>&1 ) &
"$here/perf-run.sh" --keep stream-long "$steps"
wait
