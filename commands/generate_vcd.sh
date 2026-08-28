#!/usr/bin/env bash
# Generate a VCD of one benchmark variant, for activity-annotated power.
#
# usage: gen_vcd.sh <bench> <variant> [cycles]
#
# Power is the primary metric for the Class G benchmarks, and probabilistic
# (vectorless) estimation cannot see the effects they are about -- register
# activity and glitch propagation both depend on real switching.  So we simulate.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$ROOT/flows/common/env.sh"

BENCH="${1:?bench}"; VARIANT="${2:?variant}"; CYCLES="${3:-400}"
BDIR="$ROOT/benchmarks/$BENCH"
VDIR="$BDIR/variants/$VARIANT"
TOP="$(python3 "$HERE/benchmeta.py" "$BDIR" --top)"

OUTDIR="$ROOT/build/vcd/$BENCH"
mkdir -p "$OUTDIR"
TB="$OUTDIR/tb_${TOP}.sv"
VCD="$OUTDIR/${VARIANT}.vcd"

# The file that actually declares the top module (benchmarks may have submodules).
TOPSRC="$(grep -l "module[[:space:]]\+$TOP\b" "$VDIR"/*.sv | head -1)"
[ -n "$TOPSRC" ] || { echo "gen_vcd: cannot find declaration of $TOP" >&2; exit 1; }

python3 "$HERE/gen_tb.py" "$TOPSRC" --top "$TOP" --out "$TB" --cycles "$CYCLES" >/dev/null

"$IVERILOG_BIN" -g2012 -o "$OUTDIR/${VARIANT}.vvp" -s "tb_${TOP}" \
    "$TB" "$VDIR"/*.sv 2>/dev/null
"${VVP_BIN:-$HOME/Utils/oss-cad-suite/bin/vvp}" "$OUTDIR/${VARIANT}.vvp" \
    "+vcd=$VCD" "+cycles=$CYCLES" > /dev/null 2>&1

[ -s "$VCD" ] || { echo "gen_vcd: no VCD produced for $BENCH/$VARIANT" >&2; exit 1; }
echo "$VCD"
