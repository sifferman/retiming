#!/usr/bin/env bash
# Verify every benchmark's reference solution against its original.
#
# Benchmarks declared latency_preserving are checked cycle-for-cycle.  Those with a
# latency_delta are checked with that skew and a masked reset-settling window --
# and are reported separately, because a skewed pass is a weaker claim.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CYCLES="${CYCLES:-3000}"

pass=0; fail=0; skewed=0
declare -a failed=()

for b in "$ROOT"/benchmarks/*/; do
  name="$(basename "$b")"
  [ -d "$b/variants/orig" ] || continue
  delta="$(python3 "$HERE/benchmeta.py" "$b" 2>/dev/null | sed -n 's/^latency_delta=\([0-9]*\).*/\1/p')"
  args=(--cycles "$CYCLES")
  tag="strict"
  if [ -n "$delta" ] && [ "$delta" != "0" ]; then
    args+=(--skew "$delta"); tag="skew=$delta"
  fi
  out="$(python3 "$HERE/check_equiv.py" "$b" "${args[@]}" 2>&1)"
  if grep -q "RESULT: PASS" <<< "$out"; then
    printf "  %-34s PASS  (%s)\n" "$name" "$tag"
    pass=$((pass+1)); [ "$tag" != "strict" ] && skewed=$((skewed+1))
  else
    printf "  %-34s FAIL  (%s)\n" "$name" "$tag"
    grep -E "RESULT|line [0-9]+" <<< "$out" | head -4 | sed 's/^/      /'
    fail=$((fail+1)); failed+=("$name")
  fi
done

echo
echo "equivalence: $pass pass ($skewed of them latency-skewed), $fail fail"
[ $fail -gt 0 ] && { echo "failed: ${failed[*]}"; exit 1; }
exit 0
