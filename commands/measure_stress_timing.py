#!/usr/bin/env python3
"""Compare configs at a deliberately INFEASIBLE period, scoring on WNS/TNS.

WHY NOT Fmax
Fmax rewards whatever effort the tool decided to spend.  Genus and Innovus both stop
optimising the moment they meet, so at a feasible period every config lands at
essentially the same slack: across 52 routed configs the reg2reg WNS was ~0.000 for
almost all of them, with differences in the third decimal.  Meanwhile wirelength
varied from -48% to +82%.  Reading Fmax there measures the constraint, not the design.

It is also unfair in a subtler way: route_opt_design will grind for a long time to
close a tight-but-reachable period, so a config that is merely harder looks equal to
one that is easier, having silently consumed more runtime to get there.

THE STRESS POINT
Constrain below what the FASTEST config can achieve.  Then every config fails, every
tool is at maximum effort, and WNS/TNS measure how badly each structure falls short.
This is the same regime that makes `period - wns` invariant -- the tool is pushing as
hard as it can, so what comes back describes the design rather than the target.

TNS over all violating paths matters more than WNS here.  One worst path is a single
sample; when a design is failing everywhere, the total is what says whether the
structure is broadly bad or has one awkward path.
"""

from pathlib import Path
import sys

import argparse
import json
import subprocess
import threading
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parent.parent
CONFIGS = [("orig", "off"), ("orig", "on"), ("retimed", "off"), ("directive", "off")]

JOB_SEM = threading.Semaphore(1)

def stress_period(cfgs, factor):
    """Below the fastest config's floor, so nothing can meet."""
    mins = [d["min_period_ns"] for k, d in cfgs.items()
            if not k.startswith("_") and d.get("min_period_ns")]
    return round(min(mins) * factor, 4) if mins else None

def one(job):
    """One config at one period. Holds a slot from the global job semaphore for the
    whole synth+route, so total concurrent tool jobs never exceeds the cap no matter
    how many benchmarks are in flight. NEVER raises: a TimeoutExpired escaping this function
    propagated out of ThreadPoolExecutor.map and killed the whole sweep after r06, so
    10 benchmarks were never measured at all. A run that will not finish inside the
    budget is itself a result -- at a deliberately infeasible period, a route that
    grinds for 90 minutes has failed to close, which is what we were asking."""
    bench, variant, mode, period = job
    tag = f"{variant}__genus_{mode}_p{period:g}"
    with JOB_SEM:
      try:
          subprocess.run([str(ROOT / "commands" / "run_genus.sh"), bench, variant, mode,
                          f"{period:g}"], capture_output=True, text=True, timeout=2400)
      except subprocess.TimeoutExpired:
          return dict(bench=bench, variant=variant, mode=mode, period=period,
                      wns=None, tns=None, note="synth timeout")
      subprocess.run([sys.executable, str(ROOT / "commands" / "parse_tool_result.py"),
                      str(ROOT / "results" / bench / tag)], capture_output=True, text=True)
      try:
          subprocess.run([str(ROOT / "commands" / "run_innovus.sh"), bench, variant, tag,
                          "0.7"], capture_output=True, text=True, timeout=2700)
      except subprocess.TimeoutExpired:
          return dict(bench=bench, variant=variant, mode=mode, period=period,
                      wns=None, tns=None, note="route timeout (did not close)")
      cands = sorted((ROOT / "results" / bench).glob(f"{tag}__innovus*"),
                     key=lambda q: q.stat().st_mtime, reverse=True)
      for c in cands:
          subprocess.run([sys.executable, str(ROOT / "commands" / "parse_tool_result.py"),
                          str(c), "innovus"], capture_output=True, text=True)
          mj = c / "metrics.json"
          if mj.exists():
              d = json.loads(mj.read_text())
              return dict(bench=bench, variant=variant, mode=mode, period=period,
                          wns=d.get("postroute_wns_reg2reg"),
                          tns=d.get("postroute_tns_reg2reg"),
                          viol=d.get("postroute_violating_reg2reg"),
                          wl=d.get("routed_wirelength_um"),
                          rs=d.get("path_route_share_pct"),
                          ovfl=d.get("overflow_route_v_pct"))
      return dict(bench=bench, variant=variant, mode=mode, period=period, wns=None)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--factor", type=float, default=0.7,
                    help="stress period as a fraction of the fastest config's floor")
    ap.add_argument("--state", default="results/fmax_n45.json")
    ap.add_argument("--only", default=None)
    ap.add_argument("--max-tighten", type=int, default=4,
                    help="how many times to cut the period when configs still meet")
    ap.add_argument("--out", default="results/stress_wns.json")
    args = ap.parse_args()

    state = json.loads((ROOT / args.state).read_text())
    global JOB_SEM
    JOB_SEM = threading.Semaphore(args.jobs)
    benches = sorted(p.name for p in (ROOT / "benchmarks").iterdir()
                     if (p / "variants" / "orig").is_dir())
    if args.only:
        want = set(args.only.split(","))
        benches = [b for b in benches if b in want]

    done = set()
    for prev in (args.out,):
        pp = ROOT / prev
        if not pp.exists():
            continue
        try:
            for r in json.loads(pp.read_text()):
                if r.get("stressed"):
                    done.add(r["bench"])
        except (json.JSONDecodeError, KeyError):
            pass

    todo = [b for b in benches if b not in done]
    print(f"{len(done)} benchmark(s) already stressed, {len(todo)} to do")
    print(f"total concurrent tool jobs capped at {args.jobs}\n")

    results = []
    lock = threading.Lock()

    def do_bench(b):
        """Tighten until every config of this benchmark fails. Sequential within the
        benchmark (each period depends on the last), parallel across benchmarks."""
        out = []
        cfgs = state.get(b) or {}
        p0 = stress_period(cfgs, args.factor)
        if not p0:
            return b, out, "no measured floor"
        variants = [(v, m) for v, m in CONFIGS
                    if (ROOT / "benchmarks" / b / "variants" / v).is_dir()]
        p = p0
        for attempt in range(args.max_tighten):
            with ThreadPoolExecutor(max_workers=len(variants)) as ex:
                batch = list(ex.map(one, [(b, v, m, p) for v, m in variants]))
            met = [r for r in batch if r.get("wns") is not None and r["wns"] >= 0]
            out += [dict(r, attempt=attempt, stressed=not met) for r in batch]
            with lock:
                results.extend(out[-len(batch):])
                (ROOT / args.out).write_text(json.dumps(results, indent=2))
            if not met:
                return b, out, f"STRESSED at p={p:g}"
            achieved = min((r["period"] - r["wns"]) for r in met
                           if r.get("wns") is not None)
            p = round(min(p * 0.7, achieved * 0.9), 4)
        return b, out, f"not fully stressed after {args.max_tighten} tightenings"

    fan = max(1, args.jobs // 2)
    with ThreadPoolExecutor(max_workers=fan) as ex:
        for b, rows, why in ex.map(do_bench, todo):
            print(f"  {b[:30]:<32}{why}")
            for r in rows[-4:]:
                print(f"      {r['variant']:<10}{r['mode']:<4}"
                      f"WNS={str(r.get('wns')):>8} TNS={str(r.get('tns')):>10} "
                      f"viol={str(r.get('viol')):>6} WL={str(r.get('wl')):>10}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
