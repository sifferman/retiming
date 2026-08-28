#!/usr/bin/env python3
"""Place-and-route the benchmarks whose primary metric only exists after routing.

Wirelength and post-route Fmax cannot be scored from synthesis, so r05 (fanout),
r21/r22 (wire load) and r28 (net-delay-dominated) need Innovus.

WHICH NETLIST: each config is routed from its COMMON-PERIOD netlist, not from its own
Fmax netlist and definitely not from a phase-A probe.  The probe netlists are
synthesised against an impossible constraint -- maximum area, maximum effort -- so
routing one would measure that, not the variant.  And routing each config at its own
period would confound period with variant, which is the whole thing the common period
exists to avoid.
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
CONGESTED = {
    "r28_congestion_wire_split":   (4.0, 3, 0.3),
    "r21_wire_pipeline_cross_die": (4.0, 3, 0.3),
    "r22_fanout_wire_load":        (1.0, 4, 0.15),
}

CONFIGS = [("orig", "off"), ("orig", "on"), ("retimed", "off"), ("directive", "off")]

def load_meta(benchmark_directory):
    return Benchmark(benchmark_directory).fields

def choose_netlist_tag(bench, variant, mode, period):
    """The genus run directory to hand Innovus, preferring the common period."""
    want = ROOT / "results" / bench / f"{variant}__genus_{mode}_p{period:g}"
    if (want / "metrics.json").exists():
        return want.name
    best = None
    for mj in (ROOT / "results" / bench).glob(f"{variant}__genus_{mode}_p*/metrics.json"):
        try:
            d = json.loads(mj.read_text())
        except Exception:
            continue
        if d.get("timing_status") != "MET":
            continue
        p = float(mj.parent.name.rsplit("_p", 1)[-1])
        if best is None or p > best[0]:
            best = (p, mj.parent.name)
    return best[1] if best else None

def one(job):
    bench, variant, mode, tag, density, aspect, max_layer, blockage = job
    r = subprocess.run([str(ROOT / "commands" / "run_innovus.sh"), bench, variant, tag,
                        str(density), str(aspect), str(max_layer), str(blockage)],
                       capture_output=True, text=True, timeout=3600)
    cands = sorted((ROOT / "results" / bench).glob(f"{tag}__innovus*"),
                   key=lambda q: q.stat().st_mtime, reverse=True)
    for cand in cands:
        subprocess.run([sys.executable, str(ROOT / "commands" / "parse_tool_result.py"),
                        str(cand), "innovus"], capture_output=True, text=True)
        mj = cand / "metrics.json"
        if mj.exists():
            d = json.loads(mj.read_text())
            return (bench, variant, mode, d.get("routed_wirelength_um"),
                    f"{d.get('postroute_timing_status')} "
                    f"route={d.get('path_route_share_pct')}% "
                    f"ovflV={d.get('overflow_route_v_pct')}%")
    return bench, variant, mode, None, f"no metrics (rc={r.returncode})"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--benches", default="r05_fsm_high_fanout,r21_wire_pipeline_cross_die,"
                                         "r22_fanout_wire_load,r28_congestion_wire_split")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--state", default="results/fmax_n45.json")
    ap.add_argument("--open", action="store_true",
                    help="force the open routing stack everywhere, ignoring the "
                         "per-benchmark congestion settings")
    args = ap.parse_args()

    state = json.loads((ROOT / args.state).read_text())
    jobs = []
    for b in args.benches.split(","):
        common = (state.get(b) or {}).get("_common_period_ns")
        meta = subprocess.run([sys.executable, str(ROOT / "commands" / "read_benchmark_field.py"),
                               str(ROOT / "benchmarks" / b)],
                              capture_output=True, text=True).stdout
        density = 0.6
        for line in meta.splitlines():
            if line.startswith("core_density="):
                density = float(line.split("=", 1)[1])
        for v, m in CONFIGS:
            if not (ROOT / "benchmarks" / b / "variants" / v).is_dir():
                continue
            tag = choose_netlist_tag(b, v, m, common) if common else None
            if not tag:
                print(f"  SKIP {b} {v} {m}: no suitable netlist")
                continue
            if b in CONGESTED and not args.open:
                asp, ml, blk = CONGESTED[b]
                jobs.append((b, v, m, tag, density, asp, ml, blk))
            else:
                jobs.append((b, v, m, tag, density, 1.0,
                             int(os.environ.get("PDK_MAX_ROUTE_LAYER", 10)), 0))

    print(f"{len(jobs)} PnR run(s) at {args.jobs} concurrent")
    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        for b, v, m, wl, st in ex.map(one, jobs):
            print(f"  {b[:30]:<32}{v:<10}{m:<5}wirelength={str(wl):>10}  {st}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
