#!/usr/bin/env bash
# Place-and-route a previously synthesised netlist.
#
# usage: run_innovus.sh <bench> <variant> <genus_tag> [density]
#   genus_tag is the results subdirectory produced by run_genus.sh,
#   e.g. orig__genus_on_p5.0
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/eq.sh"

BENCH="${1:?bench}"; VARIANT="${2:?variant}"; GTAG="${3:?genus tag}"
DENSITY="${4:-0.55}"
# Core aspect ratio.  A long, thin core forces nets to actually traverse distance,
# which is how the fanout/cloning benchmarks get a physical effect worth measuring:
# on a square die of this size the high-fanout net is simply not long enough for
# cloning to recover anything.
ASPECT="${5:-1.0}"
# Congestion axis: cap the signal routing stack and optionally blockade the core.
# Reaching net-delay-dominated territory is the whole point -- see flows/innovus/pnr.tcl.
# Default to the PDK's full stack, not a literal 5 -- on nangate45 (10 metals)
# a hardcoded 5 would silently halve the routing resources on every run.
MAX_LAYER="${6:-$PDK_MAX_ROUTE_LAYER}"
BLOCKAGE="${7:-0}"
# Wire-hostile emulation: scale extracted RC. gf180 at a few thousand cells cannot
# be net-dominated on physics alone (measured 0.5% route share), so this is how the
# regime is reached. Explicitly an emulation knob.
RC_SCALE="${8:-1}"

BDIR="$RETIMING_ROOT/benchmarks/$BENCH"
# Top module from bench.yaml, not the first module in the first file -- see the
# note in run_genus.sh for why the filename heuristic is wrong.
TOP="$(python3 "$HERE/benchmeta.py" "$BDIR" --top)"
TAG="${GTAG}__innovus_d${DENSITY}"
[ "$ASPECT" != "1.0" ] && TAG="${TAG}_ar${ASPECT}"
[ "$MAX_LAYER" != "$PDK_MAX_ROUTE_LAYER" ] && TAG="${TAG}_m${MAX_LAYER}"
# An alt-opt route must not overwrite its own baseline: same netlist, same density,
# different optimisation -- the tag is the only thing separating them.
[ "${RT_ALT_OPT:-0}" = "1" ] && TAG="${TAG}_altopt"
[ "$BLOCKAGE" != "0" ] && TAG="${TAG}_blk${BLOCKAGE}"
[ "$RC_SCALE" != "1" ] && TAG="${TAG}_rc${RC_SCALE}"
ROUT="results/$BENCH/$TAG"

echo ">>> PnR $BENCH/$VARIANT from $GTAG  density=$DENSITY aspect=$ASPECT top=$TOP"

ENVTMP="$(mktemp)"
cat > "$ENVTMP" <<ENVEOF
export RT_TOP="$TOP"
export RT_NETLIST="results/$BENCH/$GTAG/${TOP}_netlist.v"
export RT_SDC="results/$BENCH/$GTAG/${TOP}.sdc"
export RT_OUT="$ROUT"
export RT_ALT_OPT="${RT_ALT_OPT:-0}"
export RT_LIB="\$HOME/$REMOTE_ROOT/pdk/lib/$PDK_LIB_BASENAME"
export RT_TECH_LEF="\$HOME/$REMOTE_ROOT/pdk/lef/$(basename "$PDK_TECH_LEF")"
export RT_SC_LEF="\$HOME/$REMOTE_ROOT/pdk/lef/$(basename "$PDK_SC_LEF")"
export RT_RC_FILE="\$HOME/$REMOTE_ROOT/pdk/setRC.tcl"
export RT_SITE="$PDK_SITE"
export RT_DENSITY="$DENSITY"
export RT_ASPECT="$ASPECT"
export RT_MAX_ROUTE_LAYER="$MAX_LAYER"
export RT_BLOCKAGE="$BLOCKAGE"
export RT_RC_SCALE="$RC_SCALE"
export RT_PDK="$RT_PDK"
export RT_METAL="$PDK_METAL"
export RT_DONT_USE="$PDK_DONT_USE"
export RT_CLKBUFS="$PDK_CLKBUFS"
export RT_ROOT_CLKBUF="$PDK_ROOT_CLKBUF"
export RT_TIEHI="$PDK_TIEHI"
export RT_TIELO="$PDK_TIELO"
ENVEOF

eq_ssh "mkdir -p ~/$REMOTE_ROOT/envs" 2>&1 | eq_clean
eq_ssh "cat > ~/$REMOTE_ROOT/envs/$BENCH.$TAG.env" < "$ENVTMP" 2>&1 | eq_clean
rm -f "$ENVTMP"

eq_ssh "cd ~/$REMOTE_ROOT && bash flows/innovus/remote_run.sh envs/$BENCH.$TAG.env" \
    < /dev/null 2>&1 | eq_clean
eq_pull "$ROUT" "$RETIMING_ROOT"
echo "<<< $RETIMING_ROOT/$ROUT"
