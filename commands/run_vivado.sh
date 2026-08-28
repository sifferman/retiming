#!/usr/bin/env bash
# Run Vivado synth+impl on one benchmark variant on eq1 and pull results back.
#
# usage: run_vivado.sh <bench> <variant> <retime_mode:on|off> [period_ns]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/eq.sh"

BENCH="${1:?bench}"; VARIANT="${2:-orig}"; RETIME="${3:-on}"; PERIOD="${4:-}"
BDIR="$RETIMING_ROOT/benchmarks/$BENCH"
VDIR="$BDIR/variants/$VARIANT"
[ -d "$VDIR" ] || { echo "no such variant: $VDIR" >&2; exit 1; }

# Top module comes from bench.yaml, not from the first module in the first
# file.  Multi-module benchmarks break the filename heuristic: r15 declares
# r15_sub_a first, and elaborating that gave a combinational submodule with
# no clock port -- 15 matrix rows of a design that was not the benchmark.
TOP="$(python3 "$HERE/benchmeta.py" "$BDIR" --top)"
XDC_NAME="$(cd "$BDIR/constraints" && ls *vivado*.xdc 2>/dev/null | head -1)"
[ -n "$XDC_NAME" ] || { echo "no vivado xdc in $BDIR/constraints" >&2; exit 1; }
# The part goes in the tag: results for different device families must not
# collide, and the retiming default differs between them.
# Part as an explicit 5th argument, mirroring run_innovus.sh's density knob; then
# bench.yaml's part_usplus; then the environment default.
if [ -n "${5:-}" ]; then
  XILINX_PART="$5"
fi
PART_TAG="$(echo "$XILINX_PART" | cut -d- -f1)"
TAG="${VARIANT}__vivado_${RETIME}${PERIOD:+_p${PERIOD}}"
# The suite runs 2025.2 only, so the tag carries no version suffix. The 456 runs made
# on 2023.1 before that decision stay under their original names and are excluded by
# provenance, not by filename.
[ "$PART_TAG" != "xc7a100tcsg324" ] && [ "$PART_TAG" != "xc7a100t" ] \
  && TAG="${TAG}_${PART_TAG}"
ROUT="results/$BENCH/$TAG"
SRCS="$(cd "$RETIMING_ROOT" && ls benchmarks/$BENCH/variants/$VARIANT/*.sv | tr '\n' ' ')"

echo ">>> $BENCH/$VARIANT  vivado retime=$RETIME period=${PERIOD:-xdc} top=$TOP"

ENVTMP="$(mktemp)"
cat > "$ENVTMP" <<ENVEOF
export RT_TOP="$TOP"
export RT_SRCS="$SRCS"
export RT_XDC="benchmarks/$BENCH/constraints/$XDC_NAME"
export RT_OUT="$ROUT"
export RT_PART="$XILINX_PART"
export RT_VIVADO_VERSION="$VIVADO_VERSION"
export RT_RETIME="$RETIME"
export RT_PERIOD="$PERIOD"
ENVEOF

eq_ssh "mkdir -p ~/$REMOTE_ROOT/envs" 2>&1 | eq_clean
eq_ssh "cat > ~/$REMOTE_ROOT/envs/$BENCH.$TAG.env" < "$ENVTMP" 2>&1 | eq_clean
rm -f "$ENVTMP"

eq_ssh "cd ~/$REMOTE_ROOT && bash flows/vivado/remote_run.sh envs/$BENCH.$TAG.env" \
    < /dev/null 2>&1 | eq_clean
eq_pull "$ROUT" "$RETIMING_ROOT"
echo "<<< $RETIMING_ROOT/$ROUT"
