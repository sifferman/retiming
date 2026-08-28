#!/usr/bin/env bash
# Executed ON eq1.  Takes one argument: an env file defining the RT_* variables.
#
# Note the `< /dev/null` on the genus invocation.  Without it, Genus inherits the
# ssh stdin and happily consumes the remainder of the driving shell script as if
# it were Tcl.  That failure mode is silent and extremely confusing.
set -uo pipefail

ENVFILE="${1:?env file}"
# shellcheck disable=SC1090
source "$ENVFILE"

export CDS_SKIP_OS_CHECK_ON_STARTUP=1
export LD_LIBRARY_PATH="$HOME/Utils/eda-compat-libs:${LD_LIBRARY_PATH:-}"
GENUS=/mada/software/cadence/DDI231/GENUS231/bin/genus

mkdir -p "$RT_OUT"
START=$(date +%s)
"$GENUS" -no_gui -files flows/genus/syn.tcl -log "$RT_OUT/genus" \
    > "$RT_OUT/genus.stdout" 2>&1 < /dev/null
RC=$?
END=$(date +%s)
echo "WALL_SECONDS $((END-START))" > "$RT_OUT/wall.txt"
echo "GENUS_EXIT $RC"
grep -E "^(RT_INFO|RT_DONE)" "$RT_OUT/genus.stdout" || true
grep -iE "^Error" "$RT_OUT/genus.stdout" | head -5 || true
exit $RC
