#!/usr/bin/env python3
"""Run the measurement matrix for one or more benchmarks and collect results.

Configurations measured per benchmark
------------------------------------
  orig      / retime off     the no-retiming baseline
  orig      / retime on      what the tool achieves unaided
  directive / retime off     the tool driven only by the benchmark's own
                             directives.tcl -- i.e. can knobs alone do it?
  retimed   / retime off     the hand-written reference, tool retiming disabled
                             so we measure the RTL, not the tool

Fmax is taken as the tightest period in the grid that met timing.  A grid rather
than a binary search, because synthesis QoR is not monotonic in the constraint
(measured on r01: MET at 3.62 ns, VIOLATED at 4.09 ns in the same config).

Concurrency is capped globally: eq1 is a shared 24-core machine on a shared
license server.
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from benchmark_lib.benchmark import Benchmark

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import argparse
import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parent.parent

CONFIGS_BY_TOOL = {
    "genus": [("orig", "off"), ("orig", "on"),
              ("directive", "off"), ("retimed", "off")],
    "vivado": [("orig", "off"), ("orig", "on"),
               ("directive", "on"), ("retimed", "off")],
    "yosys": [("orig", "off"), ("orig", "on"),
              ("directive", "on"), ("retimed", "off")],
    "openroad_syn": [("orig", "none"), ("directive", "none"),
                     ("retimed", "none")],
}
CONFIGS = CONFIGS_BY_TOOL["genus"]

DIR_TAG = {"openroad_syn": "orsyn"}

def load_meta(benchmark_directory):
    return Benchmark(benchmark_directory).fields

def one_run(tool, bench, variant, mode, period, part=None):
    tag = f"{variant}__{DIR_TAG.get(tool, tool)}_{mode}_p{period}"
    if part:
        tag = f"{tag}_{part.split('-')[0]}"
    out = ROOT / "results" / bench / tag
    script = ROOT / "commands" / f"run_{tool}.sh"
    try:
        cmd = [str(script), bench, variant, mode, str(period)]
        if part:
            cmd.append(part)
        subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    except subprocess.TimeoutExpired:
        return {"bench": bench, "variant": variant, "mode": mode, "tool": tool,
                "period": period, "error": "timeout"}
    parser = ROOT / "commands" / f"parse_{tool}.py"
    subprocess.run([sys.executable, str(parser), str(out)],
                   capture_output=True, text=True)
    mj = out / "metrics.json"
    if not mj.exists():
        return {"bench": bench, "variant": variant, "mode": mode, "tool": tool,
                "period": period, "error": "no metrics"}
    m = json.loads(mj.read_text())
    m.update(bench=bench, variant=variant, mode=mode, tool=tool,
             period=period, tag=tag)
    return m

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("benches", nargs="+", help="benchmark dir names, or 'all'")
    ap.add_argument("--tool", default="genus",
                    choices=["genus", "vivado", "yosys", "openroad_syn"])
    ap.add_argument("--use-bench-part", action="store_true",
                    help="take the FPGA part from each benchmark's part_usplus, so the "
                         "two oversized benchmarks get AU15P without a global switch")
    ap.add_argument("--single", action="store_true",
                    help="one run per config at the benchmark's declared period. "
                         "Congestion and wirelength do not need an Fmax sweep, and a "
                         "5-point grid across 28 benchmarks x 4 configs x 2 parts is "
                         "1120 Vivado runs for data that one period answers.")
    ap.add_argument("--grid", default=None,
                    help="comma-separated periods; default derives from bench.yaml")
    ap.add_argument("--jobs", type=int,
                    default=int(os.environ.get("MAX_JOBS", "4")))
    ap.add_argument("--out", default=None, help="JSON file for raw rows")
    args = ap.parse_args()

    if args.benches == ["all"]:
        benches = sorted(p.name for p in (ROOT / "benchmarks").iterdir()
                         if (p / "variants" / "orig").is_dir())
    else:
        benches = args.benches

    jobs = []
    for b in benches:
        meta = load_meta(ROOT / "benchmarks" / b)
        if args.single:
            base = meta.get("fpga_clock_period_ns" if args.tool == "vivado"
                            else "clock_period_ns", 6.0)
            grid = [round(base, 3)]
        elif args.grid:
            grid = [float(x) for x in args.grid.split(",")]
        else:
            base = meta.get("clock_period_ns", 6.0)
            if args.tool == "vivado":
                base = meta.get("fpga_clock_period_ns", base * 0.7) * 2.0
            if args.tool == "vivado":
                grid = [round(base * f, 2) for f in (1.5, 1.2, 1.0, 0.8, 0.65)]
            else:
                grid = [round(base * f, 3) for f in (2.29, 1.90, 1.57, 1.29, 1.05, 0.86)]
        for variant, mode in CONFIGS_BY_TOOL[args.tool]:
            vdir = ROOT / "benchmarks" / b / "variants" / variant
            if not vdir.is_dir():
                continue
            for p in grid:
                extra = None
                if args.use_bench_part:
                    extra = meta.get("part_usplus")
                jobs.append((args.tool, b, variant, mode, p)
                            if not extra else
                            (args.tool, b, variant, mode, p, extra))

    print(f"matrix: {len(benches)} benchmark(s), {len(jobs)} runs, "
          f"{args.jobs} concurrent, tool={args.tool}")

    rows = []
    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        for i, r in enumerate(ex.map(lambda j: one_run(*j), jobs), 1):
            rows.append(r)
            status = r.get("timing_status") or r.get("error") or "?"
            print(f"  [{i}/{len(jobs)}] {r['bench']:<32} {r['variant']:<10}"
                  f"{r['mode']:<9} p={r['period']:<6} {status}")

    out = Path(args.out or (ROOT / "results" / f"matrix_{args.tool}.json"))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(rows, indent=2) + "\n")
    print(f"wrote {out} ({len(rows)} rows)")

if __name__ == "__main__":
    main()
