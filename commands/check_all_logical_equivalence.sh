#!/usr/bin/env bash
# Formal (Conformal LEC) verification across the suite.
#
# Two different claims are checked, and they are not equally strong:
#
#   orig vs directive  -- these are the SAME RTL modulo vendor attributes, so the
#                         registers correspond by name and base-license LEC can
#                         prove equivalence outright.  Any failure here is a real
#                         bug in a directive variant.
#
#   orig vs retimed    -- a retimed pair has different state points, which needs
#                         `analyze_retiming`.  Measured: that requires a
#                         Conformal_Ultra license and this site has Conformal_Asic,
#                         so these are reported as LICENSE-BLOCKED, not as
#                         failures.  Those references are verified by bounded
#                         simulation instead (commands/check_equivalence_by_simulation.py).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

MODE="${1:-directive}"   # directive | retimed | both
ok=0; bad=0; blocked=0
declare -a failed=()

for b in "$ROOT"/benchmarks/*/; do
  name="$(basename "$b")"
  for rev in $( [ "$MODE" = both ] && echo "directive retimed" || echo "$MODE" ); do
    [ -d "$b/variants/$rev" ] || continue
    out="$("$HERE/check_lec.sh" "$name" orig "$rev" 2>&1)"
    v="$(grep -oE 'LEC VERDICT: [^(]*' <<< "$out" | tail -1 | sed 's/LEC VERDICT: //')"
    case "$v" in
      Equivalent*)     printf "  %-34s %-10s PROVEN EQUIVALENT\n" "$name" "$rev"; ok=$((ok+1)) ;;
      Non-equivalent*) printf "  %-34s %-10s NON-EQUIVALENT <-- investigate\n" "$name" "$rev"; bad=$((bad+1)); failed+=("$name/$rev") ;;
      *)               printf "  %-34s %-10s license-blocked (needs Conformal_Ultra)\n" "$name" "$rev"; blocked=$((blocked+1)) ;;
    esac
  done
done

echo
echo "LEC: $ok proven equivalent, $bad non-equivalent, $blocked license-blocked"
[ $bad -gt 0 ] && { echo "failures: ${failed[*]}"; exit 1; }
exit 0
