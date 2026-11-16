#!/usr/bin/env bash
# final-check.sh: the small, reliable test that closes every UI/Core change. Needs git, bash, python3.
#
#   Performance/scripts/final-check.sh [base-ref]     changed lines vs base-ref (default: the branch upstream,
#                                                    else origin/main, else foundation; the ref is printed)
#   Performance/scripts/final-check.sh --read         only block 0: what to read for this diff
#   Performance/scripts/final-check.sh [base] --signoff FILE   print VERDICT: DONE | DONE WITH ESCALATIONS (k)
#                                                    | NOT DONE (reason) from a ticked block 4
#   Performance/scripts/final-check.sh --files F...   check whole files (no git diff)
#   Performance/scripts/final-check.sh --self-test    prove every check fires on bad fixtures, stays silent on good ones
#
# It GUARANTEES only block 1 of its output (the AUTO-VERIFIED list: exact patterns on your changed lines,
# plus the style-lint ratchet). It NEVER CLAIMS anything about timing or semantics: block 3 (MANUAL) lists
# what you must check by hand against Performance/MUST.md. Done = block 2 empty AND every block-4 line ticked
# OR escalated. Exit 1 when block 2 is not empty. Rules: Performance/RULES.md. Procedure: Performance/FINAL-CHECK.md.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
cd "$repo" || exit 2

if [ "${1:-}" = "--self-test" ]; then exec python3 "$here/fc_checks.py" --self-test; fi

style="skipped"; tmp="$(mktemp)"
if [ -x Tools/style-lint/check.sh ]; then
  if Tools/style-lint/check.sh >"$tmp" 2>&1; then style="PASS"; else style="FAIL"; cat "$tmp" >&2; fi
fi
rm -f "$tmp"
exec python3 "$here/fc_checks.py" --style "$style" "$@"
