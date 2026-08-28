#!/usr/bin/env bash
# Executed ON eq1.  Argument: env file defining the RT_* variables.
set -uo pipefail
ENVFILE="${1:?env file}"
# shellcheck disable=SC1090
source "$ENVFILE"

export CDS_SKIP_OS_CHECK_ON_STARTUP=1
# Innovus 23.1 predates this OS; libXp/libicu 50 are side-loaded from a user dir.
export LD_LIBRARY_PATH="$HOME/Utils/eda-compat-libs:${LD_LIBRARY_PATH:-}"
INNOVUS=/mada/software/cadence/DDI231/INNOVUS231/bin/innovus

mkdir -p "$RT_OUT"
START=$(date +%s)
# `< /dev/null` matters: Innovus will otherwise eat the driving script from stdin.
"$INNOVUS" -no_gui -files flows/innovus/pnr.tcl -log "$RT_OUT/innovus" \
    > "$RT_OUT/innovus.stdout" 2>&1 < /dev/null
RC=$?
END=$(date +%s)
echo "WALL_SECONDS $((END-START))" > "$RT_OUT/wall.txt"
echo "INNOVUS_EXIT $RC"
grep -E "^RT_DONE_PNR" "$RT_OUT/innovus.stdout" || true
grep -iE "^\*\*ERROR|^ERROR" "$RT_OUT/innovus.stdout" | head -8 || true
exit $RC
