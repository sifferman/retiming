#!/usr/bin/env bash
# OpenROAD integrated synthesis (sv_elaborate + synthesize) + STA. Runs locally.
#
# usage: run_openroad_syn.sh <bench> <variant> <mode:ignored> [period_ns]
#
# The mode argument exists only so this driver has the same signature as the
# others; OpenROAD's syn has no retiming control at all.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$ROOT/flows/common/env.sh"

BENCH="${1:?bench}"; VARIANT="${2:-orig}"; MODE="${3:-none}"; PERIOD="${4:-6.0}"
BDIR="$ROOT/benchmarks/$BENCH"; VDIR="$BDIR/variants/$VARIANT"
TOP="$(python3 "$HERE/benchmeta.py" "$BDIR" --top)"
BID="$(python3 "$HERE/benchmeta.py" "$BDIR" | sed -n 's/^id=//p')"
SDC="$BDIR/constraints/${BID}.sdc"
[ -f "$SDC" ] || SDC="$(ls "$BDIR/constraints"/*.sdc | grep -v -e vivado -e extra | head -1)"

LIB="$(pdk_lib_local)"

TAG="${VARIANT}__orsyn_${MODE}_p${PERIOD}"
OUT="$ROOT/results/$BENCH/$TAG"
mkdir -p "$OUT"

VCD="$ROOT/build/vcd/$BENCH/${VARIANT}.vcd"
[ -f "$VCD" ] || VCD=""

START=$(date +%s)
RT_TOP="$TOP" RT_SRCS="$(ls "$VDIR"/*.sv | tr '\n' ' ')" RT_SDC="$SDC" \
RT_OUT="$OUT" RT_LIB="$LIB" RT_TECH_LEF="$PDK_TECH_LEF" \
RT_SC_LEF="$PDK_SC_LEF" RT_RC_FILE="$PDK_RC_FILE" \
RT_PERIOD="$PERIOD" RT_PDK="$RT_PDK" RT_METAL="$PDK_METAL" \
RT_CLKBUFS="$PDK_CLKBUFS" RT_ROOT_CLKBUF="$PDK_ROOT_CLKBUF" \
RT_TIEHI="$PDK_TIEHI" RT_TIELO="$PDK_TIELO" RT_DONT_USE="$PDK_DONT_USE" RT_VCD="$VCD" \
  "$OPENROAD_BIN" -no_init -exit "$ROOT/flows/openroad/syn.tcl" \
  > "$OUT/openroad.stdout" 2>&1
RC=$?
END=$(date +%s)
echo "WALL_SECONDS $((END-START))" > "$OUT/wall.txt"
"$HERE/stamp_provenance.sh" "$OUT" "$SDC" "$VDIR"/*.sv 2>/dev/null || true

echo ">>> OR-SYN $BENCH/$VARIANT p=$PERIOD (rc=$RC)"
grep -E "^RT_DONE_ORSYN" "$OUT/openroad.stdout" || true
grep -E "^\[ERROR" "$OUT/openroad.stdout" | head -4 || true
grep -E "worst slack" "$OUT/timing.rpt" 2>/dev/null | head -2 || true
exit 0
