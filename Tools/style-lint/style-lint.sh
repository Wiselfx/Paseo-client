#!/usr/bin/env bash
# style-lint: R-4 token violations (docs/refactor/PLAN.md §RA5, docs/tickets/R2-tokens.md §6).
#
# Usage: Tools/style-lint/style-lint.sh [path] [--all]
#   path  directory to scan (default: Packages/PaseoUI/Sources/PaseoUI)
#   --all include DesignSystem/ (that folder is allowed to name literals)
#
# Prints `file:line: rule` for every violation outside DesignSystem/, then a per-file
# count and a total. It is a report: the exit code is always 0.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
path="$repo/Packages/PaseoUI/Sources/PaseoUI"
include_design_system=0

for arg in "$@"; do
  case "$arg" in
    --all) include_design_system=1 ;;
    *) path="$arg" ;;
  esac
done

[ -d "$path" ] || { echo "style-lint: no such directory: $path" >&2; exit 0; }

# rule id <TAB> extended grep pattern <TAB> optional extended grep pattern a hit must NOT match
# (R-4 token rules, then the W1 performance rules R-8: docs/perf/PERFORMANCE-RULES.md)
rules=(
  $'system-font\t\\.system\\(size:'
  $'color-literal-red\tColor\\(red:'
  $'color-literal-white\tColor\\(white:'
  $'uicolor-literal-red\tUIColor\\(red:'
  $'uicolor-literal-white\tUIColor\\(white:'
  $'corner-radius-literal\tcornerRadius: [0-9]'
  $'animation-easeOut\t\\.easeOut\\(duration:'
  $'animation-easeInOut\t\\.easeInOut\\('
  $'animation-spring\t\\.spring\\('
  $'animation-smooth\t\\.smooth\\(duration:'
  $'animation-snappy\t\\.snappy'
  $'animation-bouncy\t\\.bouncy'
  $'color-blue-tint\t\\.tint\\(\\.blue\\)'
  $'color-blue\tColor\\.blue'
  $'color-blue-foreground\t\\.foregroundStyle\\(\\.blue\\)'
  $'typography-instance\tClaudeTypography\\(\\)'
  $'haptics-uikit\tUIImpactFeedbackGenerator'
  $'haptics-uikit\tUINotificationFeedbackGenerator'
  $'haptics-sensoryFeedback\tsensoryFeedback'
  $'palette-secondary\tClaudePalette\\.secondary\\b'
  # R-8 (performance). Each pattern is a thing the W1 measurements proved harmful.
  # Rule 3: view identity must not follow a value that moves while text streams.
  $'perf-id-seqEnd\t\\.id\\(.*seqEnd\t(Color\\.clear|rowAnchor)'
  # Rule 2: `State(initialValue: Controller(...))` runs the controller on every init of the view.
  $'perf-eager-state-object\tState\\(initialValue: [A-Z][A-Za-z]*(Controller|Store|Model|Session)\\('
  $'perf-state-default-object\t@State[^=]*= [A-Z][A-Za-z]*(Controller|Engine)\\('
  # Rule 6: a synchronous system query asked from a body (the camera probe cost 1 to 2 ms a pass).
  $'perf-body-ipc\tisSourceTypeAvailable\tstatic let'
  # Rule 4: a content id built from a changing value tears the subtree down per change.
  $'perf-id-count\t\\.id\\(.*\\.(count|text|length)\\b'
  # Rule 18: a binding whose getter reads a store, built in a parent body, becomes a dependency of the
  # parent (SwiftUI evaluates it when it compares the child's inputs): the child reads the store itself.
  $'perf-binding-store-get\tget: \\{ (store|draft|controller)\\.[A-Za-z.]+ \\}'
  # Rule 19: `rest.count` / `candidate.count` on a suffix of a string inside a scan loop is O(n) per step.
  $'perf-suffix-count\t(rest|candidate)\\.count >= '
)

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

while IFS=$'\t' read -r rule pattern exclude; do
  grep -rnE --include='*.swift' -- "$pattern" "$path" 2>/dev/null |
    while IFS= read -r hit; do
      if [ -n "$exclude" ] && printf '%s' "$hit" | grep -qE -- "$exclude"; then continue; fi
      file="${hit%%:*}"
      case "$file" in
        */DesignSystem/*) [ "$include_design_system" -eq 1 ] || continue ;;
      esac
      line="${hit#*:}"; line="${line%%:*}"
      printf '%s:%s: %s\n' "$file" "$line" "$rule" >>"$tmp"
    done
done < <(printf '%s\n' "${rules[@]}")

sort -t: -k1,1 -k2,2n "$tmp" | awk '
  { print }
  {
    file = $0; sub(/:[0-9]+: .*$/, "", file)
    if (file != prev) { if (prev != "") printf "%s: %d\n", prev, count; prev = file; count = 0 }
    count++
    total++
  }
  END {
    if (prev != "") printf "%s: %d\n", prev, count
    printf "total: %d\n", total
  }'

exit 0
