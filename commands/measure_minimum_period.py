#!/usr/bin/env python3
"""Measure each config's minimum clock period directly, instead of sweeping for it.

WHY THIS REPLACES THE GRID SWEEP
--------------------------------
The sweep asked "what is the tightest period in a grid that meets timing?", which
needs the grid to straddle the answer.  Anchoring that grid went wrong three times
in a row: too loose (every point met, Fmax a lower bound), then too tight (the
orig+off BASELINE had zero meeting points, so no improvement could be computed).

The fix came from noticing that `period - wns` is invariant across the whole
violating regime.  Measured on the pre-calibration runs:

    r01  0.986 0.993 1.001 1.000 0.970 0.968  -> 0.98 ns
    r05  0.540 0.542 0.538 0.529              -> 0.537 ns
    r11  3.718 3.731 3.729                    -> 3.73 ns

Genus reports how far it missed, so one infeasible run yields the achievable period
outright.  No bracketing, no lower bounds, no unmeasurable configs.

It also explains why the earlier calibration was wrong.  It anchored on `data_path`,
which is the COMBINATIONAL segment only -- it excludes clock-to-Q, setup, clock
network latency and uncertainty, together about 0.4 ns.  r01's data_path floor read
0.546 ns against a true minimum period of 0.98; r05's read 0.110 against 0.537.  No
grid anchored on data_path could have worked.

The invariant holds only while the constraint is tight enough to force maximum
effort.  Once a config meets, wns pins to ~0 and `period - wns` just returns the
period; at very loose periods Genus coasts and it degrades (r01 at 2.95 ns reports
2.353).  So phase A always probes deliberately infeasibly and re-tightens if it
accidentally meets.

PHASES
  A  probe each config infeasibly            -> min period = period - wns
  B  re-run each config at its own min period -> confirms the prediction, and gives
                                                 area/power/cells AT its own Fmax
  C  run every config at one common period    -> apples-to-apples area/power, since
                                                 comparing them at different periods
                                                 would confound period with variant
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from benchmark_lib.benchmark import Benchmark

import argparse
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parent.parent
CONFIGS = [("orig", "off"), ("orig", "on"), ("retimed", "off"), ("directive", "off")]

def load_meta(benchmark_directory):
    return Benchmark(benchmark_directory).fields

def load_period(bench):
    out = subprocess.run([sys.executable, str(ROOT / "commands" / "read_benchmark_field.py"),
                          str(ROOT / "benchmarks" / bench)],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        if line.startswith("clock_period_ns="):
            return float(line.split("=", 1)[1])
    return 1.0

def run_one(bench, variant, mode, period):
    """Synthesise and parse; returns the metrics dict or None."""
    period = round(period, 4)
    tag = f"{variant}__genus_{mode}_p{period:g}"
    out = ROOT / "results" / bench / tag
    try:
        subprocess.run([str(ROOT / "commands" / "run_genus.sh"), bench, variant, mode,
                        f"{period:g}"], capture_output=True, text=True, timeout=2400)
    except subprocess.TimeoutExpired:
        return None
    subprocess.run([sys.executable, str(ROOT / "commands" / "parse_tool_result.py"), str(out)],
                   capture_output=True, text=True)
    mj = out / "metrics.json"
    return json.loads(mj.read_text()) if mj.exists() else None

def probe_min_period(job):
    """Phase A: find `period - wns` under an infeasible constraint."""
    bench, variant, mode, start = job
    period = start
    for _ in range(4):
        m = run_one(bench, variant, mode, period)
        if m is None:
            return bench, variant, mode, None, "run failed or timed out"
        wns, status = m.get("wns_ns"), m.get("timing_status")
        if wns is None:
            return bench, variant, mode, None, f"no timing data at p{period:g}"
        if status == "MET" or wns >= 0:
            period *= 0.5          # accidentally feasible: no information, go tighter
            continue
        return (bench, variant, mode, round(period - wns, 3),
                f"probed p{period:g}, wns={wns}")
    return bench, variant, mode, None, "met every probe; design faster than expected"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--phase", default="abc")
    ap.add_argument("--only", default=None)
    ap.add_argument("--out", default="results/fmax_n45.json")
    args = ap.parse_args()

    benches = sorted(p.name for p in (ROOT / "benchmarks").iterdir()
                     if (p / "variants" / "orig").is_dir())
    if args.only:
        want = set(args.only.split(","))
        benches = [b for b in benches if b in want]

    state_path = ROOT / args.out
    state = json.loads(state_path.read_text()) if state_path.exists() else {}

    if "a" in args.phase:
        jobs = []
        for b in benches:
            start = load_period(b) * 0.6
            for v, m in CONFIGS:
                if (ROOT / "benchmarks" / b / "variants" / v).is_dir():
                    jobs.append((b, v, m, start))
        print(f"phase A: {len(jobs)} probes at {args.jobs} concurrent")
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            for bench, v, m, minp, why in ex.map(probe_min_period, jobs):
                state.setdefault(bench, {})[f"{v}__{m}"] = {"min_period_ns": minp,
                                                            "probe": why}
                print(f"  {bench[:30]:<32}{v:<10}{m:<5}min_period={str(minp):>7} ns   {why}")
                state_path.write_text(json.dumps(state, indent=2))

    if "b" in args.phase:
        jobs = [(b, *k.split("__"), d["min_period_ns"] * 1.03)
                for b in benches for k, d in state.get(b, {}).items()
                if not k.startswith("_") and isinstance(d, dict)
                and d.get("min_period_ns")]
        print(f"\nphase B: {len(jobs)} confirmation runs at each config's own Fmax")
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            def confirm(j):
                b, v, m, p = j
                r = run_one(b, v, m, p)
                return b, v, m, p, (r or {}).get("timing_status")
            for b, v, m, p, st in ex.map(confirm, jobs):
                state[b][f"{v}__{m}"]["confirm_period_ns"] = round(p, 3)
                state[b][f"{v}__{m}"]["confirm_status"] = st
                flag = "" if st == "MET" else "   <-- prediction not confirmed"
                print(f"  {b[:30]:<32}{v:<10}{m:<5}p={p:<7.3f}{str(st):<9}{flag}")
                state_path.write_text(json.dumps(state, indent=2))

    if "c" in args.phase:
        jobs = []
        for b in benches:
            cfgs = state.get(b, {})
            mins = [d["min_period_ns"] for d in cfgs.values() if d.get("min_period_ns")]
            if not mins:
                continue
            common = round(max(mins) * 1.03, 3)
            state[b]["_common_period_ns"] = common
            for k in cfgs:
                if k.startswith("_"):
                    continue
                v, m = k.split("__")
                if abs((cfgs[k].get("confirm_period_ns") or 0) - common) > 1e-6:
                    jobs.append((b, v, m, common))
        print(f"\nphase C: {len(jobs)} runs at each benchmark's common period")
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            def atcommon(j):
                b, v, m, p = j
                r = run_one(b, v, m, p)
                return b, v, m, p, (r or {}).get("timing_status")
            for b, v, m, p, st in ex.map(atcommon, jobs):
                print(f"  {b[:30]:<32}{v:<10}{m:<5}p={p:<7.3f}{st}")
        state_path.write_text(json.dumps(state, indent=2))

    print(f"\nwrote {state_path}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
