#!/usr/bin/env python3
"""% improvement over the no-retiming baseline, per tool and metric.

Three configurations per tool:

  baseline     orig variant, tool retiming OFF   -- the no-retiming reference
  tool-auto    the tool retiming by itself: best of (orig, retiming on) and the
               directive variant, whose directives.tcl enables it
  manual       retimed variant with tool retiming OFF, so what is measured is the
               hand-written RTL rather than the tool

Improvements are computed WITHIN a benchmark and only then summarised across
benchmarks. Pooling first is meaningless: the tightest period any benchmark met
belongs to the easiest benchmark, so a pooled baseline gets compared against a
different design's result. (The first version of this script did exactly that and
produced things like -265% cells.)

Comparison basis, per benchmark
-------------------------------
Fmax uses each configuration's own tightest period that met timing. A
configuration whose tightest SWEPT period still met timing is excluded: its Fmax
is only a lower bound, so the ratio would understate it.

Every other metric is read at the tightest period that ALL configurations of that
benchmark met. Comparing area or power at each config's own Fmax would be unfair --
a design pushed to a tighter constraint spends area to get there.

Sign convention: positive always means better than baseline, for both
higher-is-better (Fmax) and lower-is-better (power, area, cells, wirelength,
runtime) metrics.
"""

from pathlib import Path
import sys

import csv
import json
import statistics
from collections import defaultdict

ROOT = Path(__file__).resolve().parent.parent

METRICS = [
    ("fmax",                 "Fmax",         False),
    ("power_mw",             "Power",        True),
    ("area_um2",             "Area",         True),
    ("num_cells",            "Cells",        True),
    ("routed_wirelength_um", "Wirelength",   True),
    ("wall_seconds",         "Compile time", True),
]

TOOLS = {
    "genus":        (("orig", "off"), [("orig", "on"), ("directive", "off"),
                                       ("directive", "on"), ("orig", "on_reset")],
                     ("retimed", "off")),
    "vivado":       (("orig", "off"), [("orig", "on"), ("directive", "on")],
                     ("retimed", "off")),
    "yosys":        (("orig", "off"), [("orig", "on"), ("directive", "on")],
                     ("retimed", "off")),
    "openroad_syn": (("orig", None), [], ("retimed", None)),
    "innovus":      (("orig", "off"), [("orig", "on"), ("directive", "off")],
                     ("retimed", "off")),
    "innovus:cong": (("orig", "off"), [("orig", "on"), ("directive", "off")],
                     ("retimed", "off")),
}

TOOL_LABELS = {
    "genus":        "Genus 23.1\nnangate45, synthesis",
    "yosys":        "yosys + ABC retime\nnangate45, synthesis",
    "openroad_syn": "OpenROAD syn\nnangate45, synthesis",
    "vivado":       "Vivado 2023.1\nArtix-7, synth+impl",
    "innovus":      "Innovus 23.1\nnangate45, post-route",
    "innovus:cong": "Innovus 23.1\nnangate45, congested",
}

NO_AUTO_REASON = {"openroad_syn": "OpenROAD syn has\nno retiming at all"}

def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None

def main():
    rows = list(csv.DictReader((ROOT / "results" / "results.csv").open()))
    for r in rows:
        r["_p"] = num(r.get("period_ns"))
        r["_met"] = (r.get("timing_status") == "MET"
                     or r.get("postroute_timing_status") == "MET")

    by = defaultdict(list)
    for r in rows:
        by[(r["tool"], r["bench"])].append(r)

    per_bench = defaultdict(lambda: defaultdict(dict))   # tool -> metric -> {series: [vals]}
    samples = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    detail = []

    for tool, (base_sel, auto_sels, man_sel) in TOOLS.items():
        for (t, bench), rs in by.items():
            if t != tool:
                continue

            def sel(sels):
                out = []
                for v, m in sels:
                    out += [r for r in rs if r["variant"] == v
                            and (m is None or r["mode"] == m)]
                return out

            base, auto, man = sel([base_sel]), sel(auto_sels), sel([man_sel])
            if not base or not man:
                continue

            def q(p):
                return None if p is None else round(p, 3)

            def met_ps(g):
                return {q(r["_p"]) for r in g if r["_met"] and r["_p"] is not None}

            def swept_ps(g):
                return {q(r["_p"]) for r in g if r["_p"] is not None}

            def fmax(g):
                """Fmax in MHz, or None if unusable (nothing met, or lower-bounded)."""
                mp, sp = met_ps(g), swept_ps(g)
                if not mp or not sp:
                    return None
                if min(mp) <= min(sp) + 1e-9:
                    return None
                return 1000.0 / min(mp)

            fb, fa, fm = fmax(base), fmax(auto) if auto else None, fmax(man)
            if fb:
                if fa:
                    samples[tool]["fmax"]["auto"].append((fa - fb) / fb * 100.0)
                    detail.append((tool, bench, "fmax", "auto", (fa - fb) / fb * 100.0))
                if fm:
                    samples[tool]["fmax"]["manual"].append((fm - fb) / fb * 100.0)
                    detail.append((tool, bench, "fmax", "manual", (fm - fb) / fb * 100.0))

            groups = [base, man] + ([auto] if auto else [])
            sets = [met_ps(g) for g in groups]
            common = set.intersection(*sets) if all(sets) else set()
            if not common:
                continue
            cp = min(common)

            def val(g, key):
                vs = [num(r.get(key)) for r in g
                      if r["_met"] and q(r["_p"]) == cp and num(r.get(key)) is not None]
                return min(vs) if vs else None

            for key, _lab, lower in METRICS:
                if key == "fmax":
                    continue
                b = val(base, key)
                if b in (None, 0):
                    continue
                for name, g in (("auto", auto), ("manual", man)):
                    if not g:
                        continue
                    v = val(g, key)
                    if v is None:
                        continue
                    imp = ((b - v) / b * 100.0) if lower else ((v - b) / b * 100.0)
                    samples[tool][key][name].append(imp)
                    detail.append((tool, bench, key, name, imp))

    out = {}
    for tool in TOOLS:
        if tool not in samples:
            continue
        e = {"label": TOOL_LABELS.get(tool, tool),
             "no_auto_reason": NO_AUTO_REASON.get(tool), "metrics": {}}
        for key, label, lower in METRICS:
            d = samples[tool].get(key, {})
            m = {}
            for name in ("auto", "manual"):
                vs = sorted(d.get(name, []))
                if not vs:
                    m[name] = None
                    continue
                def q(p):
                    if len(vs) == 1:
                        return vs[0]
                    i = p * (len(vs) - 1)
                    lo, hi = int(i), min(int(i) + 1, len(vs) - 1)
                    return vs[lo] + (vs[hi] - vs[lo]) * (i - lo)
                m[name] = {"median": statistics.median(vs), "n": len(vs),
                           "q1": q(0.25), "q3": q(0.75),
                           "min": vs[0], "max": vs[-1]}
            e["metrics"][key] = {"label": label, "lower_is_better": lower, **m}
        out[tool] = e

    (ROOT / "results" / "improvements.json").write_text(json.dumps(out, indent=2) + "\n")

    print(f"{'tool':<14}{'metric':<14}{'tool-auto (median, n)':>24}{'manual (median, n)':>22}")
    for tool, e in out.items():
        for key, label, _ in METRICS:
            d = e["metrics"][key]
            def f(x):
                return f"{x['median']:+7.1f}%  n={x['n']:<3}" if x else f"{'--':>7}       "
            print(f"{tool:<14}{label:<14}{f(d['auto']):>24}{f(d['manual']):>22}")
    print("\nwrote results/improvements.json")
    return 0

if __name__ == "__main__":
    sys.exit(main())
