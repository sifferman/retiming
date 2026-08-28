#!/bin/bash
# Checks every 20 minutes that work is actually PROGRESSING, and restarts it if not.
#
# Why this exists: chains have twice reported success while doing nothing. A TypeError
# killed the floor stage, later stages found no input, and the pipeline still printed
# DONE -- leaving eq1 idle for 9.5 hours overnight. Process-alive is not enough either:
# a driver can sit wedged with no children. So the test is whether OUTPUT is growing.
cd /home/esifferm/GitHub/retiming
LOG=results/watchdog.log
INTERVAL=1200          # 20 minutes
STALL_LIMIT=1500       # no new output for 25 min => stalled

say(){ echo "[$(date +'%m-%d %H:%M')] $*" >> "$LOG"; }

newest_result_age() {
  # age in seconds of the most recently written metrics/log under results/
  local t
  t=$(find results -newermt "-60 minutes" \( -name 'metrics.json' -o -name '*.log' \) \
        -printf '%T@\n' 2>/dev/null | sort -rn | head -1)
  [ -z "$t" ] && { echo 999999; return; }
  echo $(( $(date +%s) - ${t%.*} ))
}

tool_jobs() {
  ps -eo cmd | grep -E 'run_(genus|innovus|vivado)\.sh [a-z0-9_]+' | grep -cv grep
}

say "watchdog started (interval ${INTERVAL}s, stall limit ${STALL_LIMIT}s)"
while true; do
  sleep "$INTERVAL"
  jobs=$(tool_jobs)
  age=$(newest_result_age)
  driver=$(ps -eo cmd | grep -cE '[r]un_all\.sh|[s]tress_wns\.py|[m]easure_fmax\.py')

  if [ "$jobs" -gt 0 ] && [ "$age" -lt "$STALL_LIMIT" ]; then
    say "OK: $jobs tool jobs, newest output ${age}s ago"
    continue
  fi
  if [ "$driver" -gt 0 ] && [ "$age" -lt "$STALL_LIMIT" ]; then
    say "OK: driver alive, newest output ${age}s ago (between stages)"
    continue
  fi

  say "STALLED: jobs=$jobs driver=$driver newest_output=${age}s -- restarting run_all.sh"
  pkill -f 'run_all\.sh' 2>/dev/null
  for p in $(ps -eo pid,cmd | grep -E '[r]un_(genus|innovus|vivado)\.sh' | awk '{print $1}'); do
    kill -9 "$p" 2>/dev/null
  done
  sleep 5
  nohup bash commands/run_full_measurement.sh >> results/run_all.log 2>&1 &
  say "restarted run_all.sh (pid $!)"
done
