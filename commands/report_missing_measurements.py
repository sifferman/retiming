#!/usr/bin/env python3
"""results/missing.csv -- every config with no measurement, and WHY.

summary.csv carries only measured post-route rows, which keeps it honest but makes the
gaps invisible: a benchmark that was never routed and one whose runs crashed look the
same (absent). This separates the two, because they need different actions -- one needs
machine time, the other needs a fix.

  PENDING_RUN     never attempted; will be filled by a future run
  FAILED_<cause>  attempted and failed; needs a fix, not a re-run
  UNROUTED        ran but produced no post-route data
"""

from pathlib import Path
import sys

import csv
import glob
import json
import os
import re

ROOT = Path(__file__).resolve().parent.parent
CONFIGS = [("orig", "off"), ("orig", "on"), ("retimed", "off"), ("directive", "off")]
TOOLS = ["innovus-nangate45", "vivado-xc7a100t", "vivado-xcau7p"]

CAUSES = [
    (r"IO Placement failed due to overutilization.*?(\d+) I/O ports",
     lambda m: f"FAILED_TOO_MANY_IO({m.group(1)} ports)"),
    (r"IMPPTN-970", lambda m: "FAILED_PIN_SPREAD"),
    (r"Could not find an HDL design", lambda m: "FAILED_RTL_NOT_PUSHED"),
    (r"IMPSP-190|IMPSP-2021", lambda m: "FAILED_PLACEMENT_DENSITY"),
    (r"utilization.*exceed", lambda m: "FAILED_OVERUTILIZED"),
]

def describe_missing_reason(bench, variant, tool):
    pat = "vivado" if tool.startswith("vivado") else "innovus"
    for d in sorted(glob.glob(f"results/{bench}/{variant}__*{pat}*/"),
                    key=os.path.getmtime, reverse=True):
        for lg in ("vivado.stdout", "innovus.log", "genus.log"):
            f = Path(d) / lg
            if not f.exists():
                continue
            txt = f.read_text(errors="replace")[-400000:]
            for rx, fn in CAUSES:
                m = re.search(rx, txt, re.S)
                if m:
                    return fn(m)
        return "UNROUTED"
    return "PENDING_RUN"

def main():
    have = set()
    for r in csv.DictReader((ROOT / "results" / "summary.csv").open()):
        have.add((r["bench"], r["tool"], r["variant"], r["mode"]))
    benches = sorted(x.name for x in (ROOT / "benchmarks").iterdir()
                     if (x / "variants" / "orig").is_dir())
    out = []
    for b in benches:
        for t in TOOLS:
            for v, m in CONFIGS:
                if not (ROOT / "benchmarks" / b / "variants" / v).is_dir():
                    continue
                if (b, t, v, m) in have:
                    continue
                out.append(dict(bench=b, tool=t, variant=v, mode=m,
                                status=describe_missing_reason(b, v, t)))
    p = ROOT / "results" / "missing.csv"
    with p.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["bench", "tool", "variant", "mode", "status"])
        w.writeheader()
        w.writerows(out)
    import collections
    c = collections.Counter(r["status"] for r in out)
    print(f"wrote {p} ({len(out)} missing configs)")
    for k, v in c.most_common():
        print(f"  {k:<34}{v:>5}")
    bad = collections.Counter(f"{r['bench']} {r['status']}" for r in out
                              if r["status"].startswith("FAILED"))
    if bad:
        print("\n  needs a FIX, not a re-run:")
        for k, v in bad.most_common(8):
            print(f"    {k}  x{v}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
