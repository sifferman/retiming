#!/usr/bin/env bash
# Run Genus synthesis on one benchmark variant on eq1 and pull results back.
#
# usage: run_genus.sh <bench_dir_name> <variant> <retime_mode> [period_ns]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/eq.sh"

BENCH="${1:?bench dir name}"
VARIANT="${2:-orig}"
RETIME="${3:-on}"
PERIOD="${4:-}"
# Fifth argument selects the timing corner.  A retiming decided at one corner is
# not necessarily the right cut at another: the balance between logic-stage delay
# and load-dominated delay shifts with voltage and temperature, so the optimal
# register position can move.  Sweeping the corner is how that gets measured.
CORNER="${5:-$PDK_CORNER_TT}"
# Corner variants only exist for PDKs that ship them. gf180 has tt/ss/ff;
# nangate45 ships a single "typical" liberty, so a corner request there is a no-op
# rather than a silently wrong filename.
if [ "$RT_PDK" = "gf180" ]; then
  REMOTE_LIB="${PDK_LIBNAME}__${CORNER}.lib"
else
  REMOTE_LIB="$PDK_LIB_BASENAME"
  if [ "$CORNER" != "$PDK_CORNER_TT" ]; then
    echo "    note: $RT_PDK has no '$CORNER' corner; using $PDK_CORNER_TT" >&2
    CORNER="$PDK_CORNER_TT"
  fi
fi

BDIR="$RETIMING_ROOT/benchmarks/$BENCH"
[ -d "$BDIR" ] || { echo "no such benchmark: $BDIR" >&2; exit 1; }
VDIR="$BDIR/variants/$VARIANT"
[ -d "$VDIR" ] || { echo "no such variant: $VDIR" >&2; exit 1; }

# Top module comes from bench.yaml, not from the first module in the first
# file.  Multi-module benchmarks break the filename heuristic: r15 declares
# r15_sub_a first, and elaborating that gave a combinational submodule with
# no clock port -- 15 matrix rows of a design that was not the benchmark.
TOP="$(python3 "$HERE/benchmeta.py" "$BDIR" --top)"
BID="$(python3 "$HERE/benchmeta.py" "$BDIR" | sed -n 's/^id=//p')"
# Select the SDC by declared benchmark id.  Globbing *.sdc and taking the
# first match is wrong: helper fragments sort ahead of the real file and
# produce a design with no clock at all.
SDC_NAME="${BID}.sdc"
[ -f "$BDIR/constraints/$SDC_NAME" ] || \
  SDC_NAME="$(cd "$BDIR/constraints" && ls *.sdc | grep -v -e vivado -e extra | head -1)"
# A variant may ship its own constraints.  That is not cheating: CLAUDE.md counts
# "adding tcl/sdc commands" as a legitimate form of manual retiming, and one
# benchmark (r26) is specifically about retiming invalidating name-based SDC
# exceptions -- whose fix necessarily includes an updated SDC.
SDC_PATH="benchmarks/$BENCH/constraints/$SDC_NAME"
if [ -f "$VDIR/override.sdc" ]; then
  SDC_PATH="benchmarks/$BENCH/variants/$VARIANT/override.sdc"
  echo "    using variant SDC override"
fi
TAG="${VARIANT}__genus_${RETIME}${PERIOD:+_p${PERIOD}}"
[ "$CORNER" != "$PDK_CORNER_TT" ] && TAG="${TAG}_c${CORNER}"
ROUT="results/$BENCH/$TAG"
SRCS="$(cd "$RETIMING_ROOT" && ls benchmarks/$BENCH/variants/$VARIANT/*.sv | tr '\n' ' ')"

EXTRA=""
[ -f "$VDIR/directives.tcl" ] && EXTRA="benchmarks/$BENCH/variants/$VARIANT/directives.tcl"
COMMON=""
[ -f "$BDIR/common.tcl" ] && COMMON="benchmarks/$BENCH/common.tcl"

echo ">>> $BENCH/$VARIANT  genus retime=$RETIME period=${PERIOD:-sdc} corner=$CORNER top=$TOP"

# RT_POWER=1 asks for activity-annotated power: simulate locally, ship the VCD.
VCD_REMOTE=""
if [ "${RT_POWER:-0}" = "1" ]; then
  if VCD_LOCAL="$("$HERE/gen_vcd.sh" "$BENCH" "$VARIANT" "${VCD_CYCLES:-400}")"; then
    VCD_REMOTE="vcd/$BENCH.$VARIANT.vcd"
    eq_ssh "mkdir -p ~/$REMOTE_ROOT/vcd" 2>&1 | eq_clean
    gzip -c "$VCD_LOCAL" | eq_ssh "gunzip -c > ~/$REMOTE_ROOT/$VCD_REMOTE" 2>&1 | eq_clean
    echo "    activity: $(du -h "$VCD_LOCAL" | cut -f1) VCD pushed"
  else
    echo "    activity: VCD generation failed, falling back to vectorless" >&2
  fi
fi

ENVTMP="$(mktemp)"
cat > "$ENVTMP" <<ENVEOF
export RT_TOP="$TOP"
export RT_SRCS="$SRCS"
export RT_SDC="$SDC_PATH"
export RT_OUT="$ROUT"
export RT_LIB="\$HOME/$REMOTE_ROOT/pdk/lib/${REMOTE_LIB}"
export RT_TECH_LEF="\$HOME/$REMOTE_ROOT/pdk/lef/$(basename "$PDK_TECH_LEF")"
export RT_SC_LEF="\$HOME/$REMOTE_ROOT/pdk/lef/$(basename "$PDK_SC_LEF")"
export RT_RETIME="$RETIME"
export RT_PERIOD="$PERIOD"
export RT_EXTRA_TCL="$EXTRA"
export RT_COMMON_TCL="$COMMON"
export RT_VCD="$VCD_REMOTE"
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

eq_ssh "cd ~/$REMOTE_ROOT && bash flows/genus/remote_run.sh envs/$BENCH.$TAG.env" \
    < /dev/null 2>&1 | eq_clean

eq_pull "$ROUT" "$RETIMING_ROOT"
"$HERE/stamp_provenance.sh" "$RETIMING_ROOT/$ROUT" \
    "$BDIR/constraints/$SDC_NAME" "$VDIR"/*.sv 2>/dev/null || true
echo "<<< $RETIMING_ROOT/$ROUT"
