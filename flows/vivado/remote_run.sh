#!/usr/bin/env bash
# Executed ON eq1.  Argument: env file defining RT_* variables.
set -uo pipefail
ENVFILE="${1:?env file}"
# shellcheck disable=SC1090
source "$ENVFILE"
# Vivado version comes from the env file, defaulting to 2025.2. Never 2023.1: the
# suite is standardised on 2025.2 (and xcau7p does not exist before it).
#
# eq1's ~/.bashrc puts 2023.1 on PATH for other projects and MUST NOT be edited, so
# the version is forced per invocation instead: strip every Xilinx entry out of the
# inherited PATH, then prepend only the tree we want. Without this, an absolute vivado
# path still finds sibling Xilinx tools from the 2023.1 tree.
VIVADO_VERSION="${RT_VIVADO_VERSION:-2025.2}"
XROOT="/mada/software/Xilinx/Vivado/$VIVADO_VERSION"
VIVADO="$XROOT/bin/vivado"
if [ ! -x "$VIVADO" ]; then
  echo "RT_ERROR: no vivado at $VIVADO" >&2
  exit 1
fi
PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/mada/software/Xilinx/' \
        | paste -sd: -)"
export PATH="$XROOT/bin:$PATH"
export XILINX_VIVADO="$XROOT"
unset XILINX_VITIS XILINX_HLS XILINX_SDX 2>/dev/null || true
echo "RT_INFO vivado_version=$VIVADO_VERSION"
mkdir -p "$RT_OUT"
START=$(date +%s)
"$VIVADO" -mode batch -nojournal -notrace \
    -log "$RT_OUT/vivado.log" \
    -source flows/vivado/run.tcl > "$RT_OUT/vivado.stdout" 2>&1 < /dev/null
RC=$?
END=$(date +%s)
echo "WALL_SECONDS $((END-START))" > "$RT_OUT/wall.txt"
echo "VIVADO_EXIT $RC"
grep -E "^(RT_INFO|RT_DONE_VIVADO)" "$RT_OUT/vivado.stdout" || true
grep -E "^ERROR" "$RT_OUT/vivado.stdout" | head -6 || true
exit $RC
