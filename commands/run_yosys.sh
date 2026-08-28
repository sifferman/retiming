#!/usr/bin/env bash
# yosys synthesis to gf180mcu, then static timing with OpenROAD's built-in STA.
#
# usage: run_yosys.sh <bench> <variant> <retime_mode:off|on> [period_ns]
#
# yosys has no `retime` pass of its own.  What it does have is ABC, whose `retime`
# command implements Hurst/Mishchenko/Brayton min-register retiming.  RT_RETIME=on
# reaches it through a custom ABC script; that is the closest thing to retiming
# available anywhere in the open-source flow, and quantifying the gap between it
# and the commercial retimers is one of the things this suite is for.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$ROOT/flows/common/env.sh"

BENCH="${1:?bench}"; VARIANT="${2:-orig}"; RETIME="${3:-off}"; PERIOD="${4:-6.0}"
BDIR="$ROOT/benchmarks/$BENCH"; VDIR="$BDIR/variants/$VARIANT"
TOP="$(python3 "$HERE/benchmeta.py" "$BDIR" --top)"
BID="$(python3 "$HERE/benchmeta.py" "$BDIR" | sed -n 's/^id=//p')"
SDC="$BDIR/constraints/${BID}.sdc"
[ -f "$SDC" ] || SDC="$(ls "$BDIR/constraints"/*.sdc | grep -v -e vivado -e extra | head -1)"

TAG="${VARIANT}__yosys_${RETIME}_p${PERIOD}"
OUT="$ROOT/results/$BENCH/$TAG"
mkdir -p "$OUT"

# Uncompressed liberty cache -- yosys and OpenSTA both want a plain .lib.
LIB="$(pdk_lib_local)"

PERIOD_PS=$(python3 -c "print(int(float('$PERIOD')*1000))")
ABC_D="-D $PERIOD_PS"
if [ "$RETIME" = "on" ]; then
  # ABC's `retime` only sees registers if yosys hands them over, which is what
  # -dff does; without it the ABC network is purely combinational logic between
  # flops and `retime` is a no-op.
  ABC_SCRIPT='+retime;strash;dch,-f;map,-B,0.9;topo;stime,-c;buffer,-c;upsize,-c;dnsize,-c'
  ABC_ARGS="-liberty $LIB -dff -script $ABC_SCRIPT"
else
  ABC_ARGS="-liberty $LIB $ABC_D"
fi

cat > "$OUT/syn.ys" <<YS
read_verilog -sv $(ls "$VDIR"/*.sv | tr '\n' ' ')
hierarchy -check -top $TOP
synth -top $TOP -flatten
dfflibmap -liberty $LIB
abc $ABC_ARGS
setundef -zero
splitnets
opt_clean -purge
stat -liberty $LIB
write_verilog -noattr $OUT/${TOP}_netlist.v
YS

START=$(date +%s)
"$YOSYS_BIN" -l "$OUT/yosys.log" "$OUT/syn.ys" > "$OUT/yosys.stdout" 2>&1
YRC=$?
MID=$(date +%s)

# Timing on the mapped netlist using OpenROAD's STA.
cat > "$OUT/sta.tcl" <<STA
# OpenROAD's read_verilog populates ODB, which requires a technology first --
# hence the LEF reads even though this step only does timing.
read_lef $PDK_TECH_LEF
read_lef $PDK_SC_LEF
read_liberty $LIB
read_verilog $OUT/${TOP}_netlist.v
link_design $TOP
set ::CLK_PERIOD $PERIOD
read_sdc $SDC
report_checks -path_delay max -format full -digits 4 > $OUT/timing.rpt
report_worst_slack -max -digits 4     >> $OUT/timing.rpt
report_tns -digits 4                  >> $OUT/timing.rpt
report_design_area                     > $OUT/area.rpt
report_power                           > $OUT/power.rpt
exit
STA
"$OPENROAD_BIN" -no_init -exit "$OUT/sta.tcl" > "$OUT/sta.stdout" 2>&1
END=$(date +%s)

echo "WALL_SECONDS $((END-START))" > "$OUT/wall.txt"
"$HERE/stamp_provenance.sh" "$OUT" "$SDC" "$VDIR"/*.sv 2>/dev/null || true
echo "YOSYS_SECONDS $((MID-START))" >> "$OUT/wall.txt"
echo ">>> $BENCH/$VARIANT yosys retime=$RETIME p=$PERIOD  (yosys rc=$YRC)"
grep -E "Chip area|worst slack|tns" "$OUT/timing.rpt" "$OUT/area.rpt" 2>/dev/null | head -5
exit 0
