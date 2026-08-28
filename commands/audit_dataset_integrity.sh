#!/usr/bin/env bash
# Audit the suite and the collected data for the failure modes that have actually
# bitten, each of which was silent when it happened:
#
#   1. a benchmark synthesised with the wrong top module (r15: the filename
#      heuristic picked a combinational submodule, 20 rows of the wrong design)
#   2. runs that completed remotely but whose transfer dropped (10 of 472)
#   3. result directories with no timing status (the symptom of both of the above,
#      and of an unconstrained design)
#   4. benchmarks missing a required file
#
# Run this before quoting any number. A sweep is not finished because it printed a
# row count.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"
fail=0

echo "== 1. top module: bench.yaml vs first-module-in-first-file =="
n=0
for b in benchmarks/*/; do
  d="$(python3 "$HERE/benchmeta.py" "$b" --top 2>/dev/null)"
  f="$(python3 "$HERE/svparse.py" "$(ls "$b"/variants/orig/*.sv 2>/dev/null | head -1)" 2>/dev/null | head -1)"
  if [ -n "$d" ] && [ -n "$f" ] && [ "$d" != "$f" ]; then
    echo "   note: $(basename "$b") declares '$d' but first module is '$f'"
    echo "         (fine as long as every runner uses benchmeta.py, which is checked below)"
    n=$((n+1))
  fi
done
[ $n -eq 0 ] && echo "   no divergence"

echo "== 2. runners must take the top from bench.yaml, not from a filename =="
bad="$(grep -l 'svparse.py' commands/*.sh 2>/dev/null || true)"
if [ -n "$bad" ]; then
  echo "   FAIL: these runners still guess the top: $bad"; fail=1
else
  echo "   ok: all runners use benchmeta.py"
fi

echo "== 3. result dirs with no usable timing status =="
missing=0
while read -r d; do
  [ -f "$d/metrics.json" ] || continue
  python3 - "$d/metrics.json" <<'PY' || missing=$((missing+1))
import json,sys
m=json.load(open(sys.argv[1]))
ok = m.get("timing_status") in ("MET","VIOLATED") or \
     m.get("postroute_timing_status") in ("MET","VIOLATED") or \
     m.get("tool") in ("openroad_syn",)
sys.exit(0 if ok else 1)
PY
done < <(find results -mindepth 2 -maxdepth 2 -type d)
if [ "$missing" -gt 0 ]; then
  echo "   WARNING: $missing run dirs have metrics but no MET/VIOLATED verdict"
  echo "            (unconstrained design, wrong top, or a crashed run)"
else
  echo "   ok: every parsed run has a timing verdict"
fi

echo "== 4. remote runs missing locally (dropped transfers) =="
if DRY_RUN=1 "$HERE/repair_pull.sh" 2>/dev/null | tail -1 | grep -q "0 missing locally"; then
  echo "   ok: local and remote inventories agree"
else
  DRY_RUN=1 "$HERE/repair_pull.sh" 2>/dev/null | tail -1 | sed 's/^/   /'
  echo "   -> run commands/refetch_missing_results.sh to recover (no re-synthesis needed)"
fi

echo "== 5. per-benchmark file completeness =="
incomplete=0
for b in benchmarks/*/; do
  miss=""
  [ -f "$b/bench.yaml" ] || miss="$miss bench.yaml"
  ls "$b"/constraints/*.sdc >/dev/null 2>&1 || miss="$miss sdc"
  for v in orig retimed directive; do
    ls "$b"/variants/$v/*.sv >/dev/null 2>&1 || miss="$miss $v"
  done
  [ -n "$miss" ] && { echo "   $(basename "$b"): missing$miss"; incomplete=1; fail=1; }
done
[ $incomplete -eq 0 ] && echo "   ok: all benchmarks complete"

echo
[ $fail -eq 0 ] && echo "audit: no blocking problems" || echo "audit: PROBLEMS FOUND (see FAIL lines)"
exit $fail
