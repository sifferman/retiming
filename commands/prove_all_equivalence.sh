#!/bin/bash
# Prove every variant pair, on donut. No license, so it does not compete with eq1.
#
# BMC rather than k-induction: `prove` failed the induction step on r20 even after the
# reset protocol was fixed, which is expected -- induction without invariants reaches
# states the design cannot actually get into. BMC to depth 20 is a real proof over ALL
# input sequences for 20 cycles, which is far stronger evidence than one 4000-cycle
# simulation trace, and it is what caught nothing today only because nothing was wrong.
cd /home/esifferm/GitHub/retiming
DEPTH="${DEPTH:-20}"
JOBS="${JOBS:-6}"
run_one() {
  b="$1"
  for pair in "orig retimed" "orig directive"; do
    set -- $pair
    [ -d "benchmarks/$b/variants/$2" ] || continue
    # A latency-changing reference needs the gold output delayed before comparing.
    SKEW=0
    grep -q "latency_preserving: false" "benchmarks/$b/bench.yaml" && SKEW=1
    timeout 2400 python3 commands/prove_equivalence_formally.py "$b" --a "$1" --b "$2" \
        --mode bmc --depth "$DEPTH" --skew "$SKEW" --timeout 2300 2>&1 | tail -1
  done
}
export -f run_one; export DEPTH
ls benchmarks | xargs -P "$JOBS" -I{} bash -c 'run_one {}'
