#!/usr/bin/env bash
# check.sh: the enforcing wrapper around style-lint.sh (R-4 tokens + R-8 performance rules).
#
# style-lint.sh only reports. This fails (exit 1) when any (file, rule) pair has MORE hits than
# Tools/style-lint/baseline.txt allows, so nothing new gets in, while the deliberate, reviewed
# exceptions already in the tree stay. A fix that removes a hit passes; run with --update after a
# reviewed change to lower (or, with justification in the PR, adjust) the baseline.
#
#   Tools/style-lint/check.sh            check against the baseline (CI)
#   Tools/style-lint/check.sh --update   rewrite the baseline from the current tree
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
baseline="$here/baseline.txt"

current="$(bash "$here/style-lint.sh" 2>/dev/null \
  | grep -E '^/.*:[0-9]+: ' \
  | sed -E "s#^$repo/##; s#:[0-9]+: # #" \
  | sort | uniq -c | awk '{print $2" "$3" "$1}' | sort)"

if [ "${1:-}" = "--update" ]; then
  printf '%s\n' "$current" > "$baseline"
  echo "baseline updated: $(wc -l < "$baseline") entries"
  exit 0
fi

fail=0
while read -r file rule count; do
  [ -n "${file:-}" ] || continue
  allowed="$(awk -v f="$file" -v r="$rule" '$1==f && $2==r {print $3}' "$baseline" 2>/dev/null)"
  allowed="${allowed:-0}"
  if [ "$count" -gt "$allowed" ]; then
    echo "style-lint: $file has $count '$rule' hit(s), baseline allows $allowed" >&2
    fail=1
  fi
done <<< "$current"

if [ "$fail" -ne 0 ]; then
  echo "style-lint: new violations. Fix them (Performance/RULES.md, AGENTS.md R-4/R-8)." >&2
  exit 1
fi
echo "style-lint: no new violations ($(wc -l < "$baseline") baseline entries)"
