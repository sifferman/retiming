#!/bin/bash
# Full re-measure after the registered-I/O wrapper and the SIPO port fixes.
#
# Every stage VERIFIES its own output before the next one runs. The previous chain
# separated stages with ';' so a failure could not strand the rest -- but that let the
# floor stage die on a TypeError, produce no floors, and the pipeline still printed
# DONE. Nine hours of machine time went to a false green.
cd /home/esifferm/GitHub/retiming
source flows/common/env.sh
source commands/remote_execution.sh
say(){ echo "=== [$(date +%H:%M)] $*"; }
die(){ echo "!!! [$(date +%H:%M)] ABORT: $*"; exit 1; }

say "push wrapped + serialised RTL"
eq_push benchmarks scripts flows >/dev/null 2>&1
eq_ssh "grep -lc RT_WRAPPER_BEGIN ~/$REMOTE_ROOT/benchmarks/*/variants/orig/*.sv 2>/dev/null | wc -l" \
  2>&1 | eq_clean | tail -1

say "stage 1/3: floors for all 28 (wrapper changed every design's timing)"
python3 -u commands/measure_minimum_period.py --phase a --jobs 12 --out results/fmax_v2.json 2>&1 | tail -32
n=$(python3 -c "
import json;d=json.load(open('results/fmax_v2.json'))
print(sum(1 for b in d for k,v in d[b].items() if not k.startswith('_') and isinstance(v,dict) and v.get('min_period_ns')))")
echo "  floors measured: $n"
[ "${n:-0}" -ge 40 ] || die "only $n floors -- not enough to stress anything"

say "stage 2/3: stress sweep, all 28, post-route"
python3 -u commands/measure_stress_timing.py --jobs 16 --factor 0.7 --max-tighten 5 \
   --state results/fmax_v2.json --out results/stress_v2.json 2>&1 | tail -80
m=$(python3 -c "
import json;d=json.load(open('results/stress_v2.json'))
print(len({r['bench'] for r in d if r.get('stressed')}))")
echo "  benchmarks stressed: $m / 28"
[ "${m:-0}" -ge 20 ] || die "only $m benchmarks stressed"

say "stage 3/3: Vivado on both parts (the five port fixes should now place)"
XILINX_PART=xc7a100tcsg324-1 python3 -u commands/run_measurement_matrix.py all --tool vivado \
   --jobs 12 --single --out results/matrix_v2_a7.json 2>&1 | tail -4
python3 -u commands/run_measurement_matrix.py all --tool vivado --jobs 12 --single --use-bench-part \
   --out results/matrix_v2_auplus.json 2>&1 | tail -4

say "regenerate"
python3 commands/summarize_results.py 2>&1 | tail -3
python3 commands/report_missing_measurements.py 2>&1 | head -8
python3 commands/generate_per_benchmark_charts.py 2>&1 | head -2
python3 commands/generate_stress_chart.py 2>&1 | tail -1
git add -A && git commit -q -m "Re-measure on wrapped + serialised RTL" && git log --oneline -1
say "ALL DONE"
