#!/usr/bin/env bash
# Re-pull result directories that exist on eq1 but are missing (or empty) locally.
#
# The transfer path to eq1 is the fragile part of this harness: scp and rsync are
# unusable (a login banner corrupts the protocol), so pulls are base64 frames over
# ssh, and a dropped frame loses the directory silently.  Measured: 4 Genus runs
# completed remotely with full reports and never arrived, which showed up only as
# "no metrics" rows in the matrix.
#
# Compute is expensive and the results are already on the remote, so repair by
# re-pulling rather than re-running.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/eq.sh"

DRY="${DRY_RUN:-0}"

# Remote inventory of run directories that have something worth pulling.
remote_list="$(eq_ssh "cd ~/$REMOTE_ROOT 2>/dev/null && \
  find results -mindepth 2 -maxdepth 2 -type d \
    \\( -name '*genus*' -o -name '*innovus*' -o -name '*vivado*' -o -name 'lec_*' \\) \
  2>/dev/null | sort" < /dev/null 2>/dev/null | grep '^results/' || true)"

[ -n "$remote_list" ] || { echo "repair_pull: could not list remote results"; exit 1; }

total=0; missing=0; pulled=0; failed=0; suspect=0
while read -r d; do
  [ -n "$d" ] || continue
  total=$((total+1))
  # "Present locally" is type-dependent: LEC runs have no timing.rpt, so testing
  # for one misclassifies every LEC directory as missing.
  case "$d" in
    */lec_*) present_marker="lec.stdout" ;;
    *)       present_marker="timing.rpt" ;;
  esac
  if [ -f "$RETIMING_ROOT/$d/metrics.json" ] || \
     [ -f "$RETIMING_ROOT/$d/$present_marker" ]; then
    continue
  fi
  missing=$((missing+1))
  if [ "$DRY" = "1" ]; then
    echo "  would pull: $d"
    continue
  fi
  if eq_pull "$d" "$RETIMING_ROOT" && \
     { [ -f "$RETIMING_ROOT/$d/$present_marker" ] || \
       [ -f "$RETIMING_ROOT/$d/metrics_tcl.json" ]; }; then
    # Guard against resurrecting a superseded run.  The remote keeps results from
    # earlier, buggy configurations, and this tool will happily re-import one:
    # measured, it pulled back an r26 run synthesised against a constraints file
    # that had no create_clock, which had already been deleted on purpose.
    # A run with no timing verdict is the signature of exactly that.
    if [ -f "$RETIMING_ROOT/$d/timing.rpt" ] && \
       ! grep -qE "Path 1:|Slack:=" "$RETIMING_ROOT/$d/timing.rpt" 2>/dev/null; then
      echo "  pulled but SUSPECT (no timed paths - likely a superseded run): $d"
      suspect=$((suspect+1))
    else
      echo "  pulled: $d"
    fi
    pulled=$((pulled+1))
  else
    echo "  FAILED: $d"
    failed=$((failed+1))
  fi
done <<< "$remote_list"

echo
echo "repair_pull: $total remote runs, $missing missing locally, $pulled recovered, $failed still failing, $suspect suspect"
[ "$suspect" -gt 0 ] && echo "  review the SUSPECT entries: a run with no timed paths usually means it was\n  produced by an older, broken configuration and should be deleted, not kept."
exit 0
