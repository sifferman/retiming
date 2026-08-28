#!/usr/bin/env bash
# Place-and-route a mapped netlist with OpenROAD (runs locally on donut).
#
# usage: run_openroad_pnr.sh <bench> <variant> <syn_tag> [density]
#   syn_tag is a results subdir holding <top>_netlist.v, e.g. orig__yosys_on_p6.0
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$ROOT/flows/common/env.sh"

BENCH="${1:?bench}"; VARIANT="${2:?variant}"; STAG="${3:?syn tag}"; DENSITY="${4:-0.55}"
BDIR="$ROOT/benchmarks/$BENCH"
TOP="$(python3 "$HERE/benchmeta.py" "$BDIR" --top)"
BID="$(python3 "$HERE/benchmeta.py" "$BDIR" | sed -n 's/^id=//p')"
SDC="$BDIR/constraints/${BID}.sdc"
[ -f "$SDC" ] || SDC="$(ls "$BDIR/constraints"/*.sdc | grep -v -e vivado -e extra | head -1)"
NETLIST="$ROOT/results/$BENCH/$STAG/${TOP}_netlist.v"
[ -f "$NETLIST" ] || { echo "no netlist: $NETLIST" >&2; exit 1; }

LIB="$(pdk_lib_local)"

# Period the netlist was synthesised at, so STA here matches synthesis intent.
PERIOD="$(sed -n 's/.*_p\([0-9.]*\)$/\1/p' <<< "$STAG")"

OUT="$ROOT/results/$BENCH/${STAG}__orpnr_d${DENSITY}"
mkdir -p "$OUT"

VCD="$ROOT/build/vcd/$BENCH/${VARIANT}.vcd"
[ -f "$VCD" ] || VCD=""

START=$(date +%s)
RT_TOP="$TOP" RT_NETLIST="$NETLIST" RT_SDC="$SDC" RT_OUT="$OUT" \
RT_LIB="$LIB" RT_TECH_LEF="$PDK_TECH_LEF" RT_SC_LEF="$PDK_SC_LEF" \
RT_RC_FILE="$PDK_RC_FILE" RT_DENSITY="$DENSITY" RT_SITE="$PDK_SITE" \
RT_PERIOD="$PERIOD" RT_PDK="$RT_PDK" RT_METAL="$PDK_METAL" \
RT_CLKBUFS="$PDK_CLKBUFS" RT_ROOT_CLKBUF="$PDK_ROOT_CLKBUF" \
RT_TIEHI="$PDK_TIEHI" RT_TIELO="$PDK_TIELO" RT_DONT_USE="$PDK_DONT_USE" RT_VCD="$VCD" \
  "$OPENROAD_BIN" -no_init -exit "$ROOT/flows/openroad/pnr.tcl" \
  > "$OUT/openroad.stdout" 2>&1
RC=$?
END=$(date +%s)
echo "WALL_SECONDS $((END-START))" > "$OUT/wall.txt"
"$HERE/stamp_provenance.sh" "$OUT" "$SDC" "$NETLIST" 2>/dev/null || true

echo ">>> OR-PnR $BENCH/$VARIANT from $STAG d=$DENSITY (rc=$RC)"
grep -E "^RT_DONE_ORPNR|^RT_WARN" "$OUT/openroad.stdout" || true
grep -E "^\[ERROR" "$OUT/openroad.stdout" | head -4 || true
exit 0
