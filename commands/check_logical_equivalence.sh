#!/usr/bin/env bash
# Formal equivalence (Cadence Conformal LEC) between two variants of a benchmark.
#
# usage: check_lec.sh <bench> [golden_variant] [revised_variant]
#
# Complements commands/check_equivalence_by_simulation.py, which is a bounded simulation check.  The
# simulation check runs on every commit because it is fast and needs no license;
# this is the formal argument.
#
# A retimed circuit is not combinationally equivalent to its original -- the state
# encoding differs -- so this leans on Conformal's `analyze_retiming` rather than
# name-based key-point mapping.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/eq.sh"

BENCH="${1:?bench}"; GOLD="${2:-orig}"; REV="${3:-retimed}"
BDIR="$RETIMING_ROOT/benchmarks/$BENCH"
TOP="$(python3 "$HERE/benchmeta.py" "$BDIR" --top)"
ROUT="results/$BENCH/lec_${GOLD}_vs_${REV}"

GOLD_SRCS="$(cd "$RETIMING_ROOT" && ls benchmarks/$BENCH/variants/$GOLD/*.sv | tr '\n' ' ')"
REV_SRCS="$(cd "$RETIMING_ROOT" && ls benchmarks/$BENCH/variants/$REV/*.sv | tr '\n' ' ')"

echo ">>> LEC $BENCH: $GOLD (golden) vs $REV (revised), top=$TOP"

DO=$(mktemp)
sed -e "s|@TOP@|$TOP|g" -e "s|@GOLDEN@|$GOLD_SRCS|g" \
    -e "s|@REVISED@|$REV_SRCS|g" -e "s|@OUT@|$ROUT|g" \
    "$RETIMING_ROOT/flows/conformal/lec.do.template" > "$DO"

eq_ssh "mkdir -p ~/$REMOTE_ROOT/$ROUT" 2>&1 | eq_clean
eq_ssh "cat > ~/$REMOTE_ROOT/$ROUT/lec.do" < "$DO" 2>&1 | eq_clean
rm -f "$DO"

eq_ssh "cd ~/$REMOTE_ROOT && \
  export CDS_SKIP_OS_CHECK_ON_STARTUP=1 && \
  export LD_LIBRARY_PATH=\$HOME/Utils/eda-compat-libs:\${LD_LIBRARY_PATH:-} && \
  /mada/software/cadence/CONFRML232/bin/lec -64 -nogui -TCLmode \
      -dofile $ROUT/lec.do > $ROUT/lec.stdout 2>&1 < /dev/null; \
  echo LEC_EXIT \$?; \
  grep -oE 'LEC_LICENSE [^/]*|LEC_MODE [^/]*|^(Equivalent|Non-equivalent|Abort)[^/]*' \
      $ROUT/lec.stdout | head -8 $ROUT/lec.stdout | head -12" \
  < /dev/null 2>&1 | eq_clean

eq_pull "$ROUT" "$RETIMING_ROOT"

# Final verdict, parsed from the summary table rather than the progress spam.
if [ -f "$RETIMING_ROOT/$ROUT/lec.stdout" ]; then
  VERDICT="$(grep -oE '^(Equivalent|Non-equivalent|Abort) +[0-9]+ +[0-9]+ +[0-9]+' \
              "$RETIMING_ROOT/$ROUT/lec.stdout" | tail -1)"
  if [ -n "$VERDICT" ]; then
    echo "    LEC VERDICT: $VERDICT   (class  PI/PO  DFF  total)"
  else
    echo "    LEC VERDICT: no compare points -- see the license note above"
  fi
fi
echo "<<< $RETIMING_ROOT/$ROUT"
