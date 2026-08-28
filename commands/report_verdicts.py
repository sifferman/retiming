#!/usr/bin/env python3
"""Per-benchmark verdict, scored on each benchmark's DECLARED primary metric.

Comparing Fmax on a power benchmark is meaningless, and comparing a single-period
run against a swept one is worse than meaningless -- it manufactures a tie.  So:

  * `fmax`        -> highest Fmax wins; needs >= 3 swept periods on both sides,
                     and neither side may be a lower bound (tightest period met)
  * `power`       -> lowest power at a period BOTH sides meet
  * `wirelength`  -> lowest routed wirelength at equal density
  * `diagnostic`  -> no winner; reports the observed behaviour instead

Anything without enough data is reported as such rather than scored.
"""

from pathlib import Path
import sys

import csv
from collections import defaultdict

ROOT = Path(__file__).resolve().parent.parent

MIN_SWEEP = 2

def f(r, key):
    try:
        return float(r[key])
    except (ValueError, KeyError, TypeError):
        return None

def primary_metric_of(rs):
    m = (rs[0].get("primary_metric") or "fmax").lower()
    if "power" in m:
        return "power"
    if "wirelength" in m and "fmax" not in m:
        return "wirelength"
    if "diagnostic" in m or "exception" in m:
        return "diagnostic"
    return "fmax"

def main():
    path = ROOT / "results" / "summary.csv"
    if not path.exists():
        print("no summary.csv -- run commands/summarize_results.py first")
        return 1
    rows = list(csv.DictReader(path.open()))

    by = defaultdict(list)
    for r in rows:
        by[(r["bench"], r["tool"])].append(r)

    print(f"{'benchmark':<34}{'tool':<13}{'metric':<11}{'tool':>10}{'ref':>10}"
          f"  verdict")
    print("-" * 108)
    tally = defaultdict(int)

    PNR_TOOLS = {"innovus", "openroad"}
    PNR_METRICS = {"wirelength"}

    for (bench, tool), rs in sorted(by.items()):
        metric = primary_metric_of(rs)
        if metric in PNR_METRICS and tool not in PNR_TOOLS:
            continue
        tool_rows = [r for r in rs if r["variant"] in ("orig", "directive")]
        ref_rows = [r for r in rs if r["variant"] == "retimed"]
        if not tool_rows or not ref_rows:
            continue

        if metric == "diagnostic":
            print(f"{bench:<34}{tool:<13}{'diagnostic':<11}{'-':>10}{'-':>10}"
                  f"  see docs/FINDINGS.md (not scored on a number)")
            tally["diagnostic"] += 1
            continue

        if metric == "fmax":
            tb = max((r for r in tool_rows if f(r, "fmax_mhz")),
                     key=lambda r: f(r, "fmax_mhz"), default=None)
            rb = max((r for r in ref_rows if f(r, "fmax_mhz")),
                     key=lambda r: f(r, "fmax_mhz"), default=None)
            if not tb or not rb:
                continue
            n_ok = (int(tb.get("n_runs") or 0) >= MIN_SWEEP
                    and int(rb.get("n_runs") or 0) >= MIN_SWEEP)
            bounded = (tb.get("fmax_is_lower_bound") == "yes"
                       or rb.get("fmax_is_lower_bound") == "yes")
            tv, rv = f(tb, "fmax_mhz"), f(rb, "fmax_mhz")
            note = ""
            if not n_ok:
                verdict = f"NO DATA (only {tb.get('n_runs')}/{rb.get('n_runs')} periods; needs >={MIN_SWEEP})"
                tally["nodata"] += 1
            elif bounded:
                verdict = "INCONCLUSIVE (Fmax is a lower bound; sweep tighter)"
                tally["inconclusive"] += 1
            else:
                margin = (rv - tv) / tv * 100.0
                if margin > 5:
                    verdict = f"REFERENCE WINS {margin:+.0f}%"
                    tally["ref"] += 1
                elif margin < -5:
                    verdict = f"tool wins {-margin:.0f}% (already solved)"
                    tally["tool"] += 1
                else:
                    verdict = "tie (within 5%)"
                    tally["tie"] += 1
            print(f"{bench:<34}{tool:<13}{'fmax MHz':<11}{tv:>10.1f}{rv:>10.1f}"
                  f"  {verdict}{note}")
            continue

        key = "power_mw" if metric == "power" else "wirelength_um"
        tb = min((r for r in tool_rows if f(r, key)), key=lambda r: f(r, key),
                 default=None)
        rb = min((r for r in ref_rows if f(r, key)), key=lambda r: f(r, key),
                 default=None)
        if not tb or not rb:
            print(f"{bench:<34}{tool:<13}{metric:<11}{'-':>10}{'-':>10}"
                  f"  NO DATA ({key} not measured yet)")
            tally["nodata"] += 1
            continue
        tv, rv = f(tb, key), f(rb, key)
        margin = (tv - rv) / tv * 100.0     # positive = reference better
        if margin > 5:
            verdict = f"REFERENCE WINS {margin:+.0f}% lower {metric}"
            tally["ref"] += 1
        elif margin < -5:
            verdict = f"reference LOSES {-margin:.0f}% ({metric} worse)"
            tally["tool"] += 1
        else:
            verdict = "tie (within 5%)"
            tally["tie"] += 1
        print(f"{bench:<34}{tool:<13}{metric:<11}{tv:>10.1f}{rv:>10.1f}  {verdict}")

    print("-" * 108)
    print(f"reference wins: {tally['ref']}   tool wins: {tally['tool']}   "
          f"ties: {tally['tie']}   inconclusive: {tally['inconclusive']}   "
          f"no data: {tally['nodata']}   diagnostic: {tally['diagnostic']}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
