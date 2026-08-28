#!/usr/bin/env python3
"""Build the maintained results CSVs from every metrics.json under results/.

Two files:
  results/results.csv   one row per (benchmark, tool, variant, mode, period) run
  results/summary.csv   one row per (benchmark, tool, variant, mode): the best
                        result across the period grid, i.e. Fmax and the QoR at it

Fmax is the tightest period that met timing, so it is only meaningful once a grid
has been swept.  Rows whose runs all violated report fmax_mhz empty rather than
guessing.
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from benchmark_lib.benchmark import Benchmark

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import csv
import os
import re
import json
from collections import defaultdict

ROOT = Path(__file__).resolve().parent.parent

RUN_FIELDS = [
    "bench", "class", "tool", "tool_version", "variant", "mode", "period_ns",
    "timing_status",

    "postroute_wns_reg2reg", "postroute_tns_reg2reg", "postroute_violating_reg2reg",

    "num_ffs", "num_ffs_pre_syn",

    "num_cells", "area_um2",
    "routed_wirelength_um", "achieved_density_pct",

    "overflow_route", "overflow_route_h_pct", "overflow_route_v_pct",
    "path_route_share_pct", "path_cell_delay_ns", "path_net_delay_ns",
    "congestion_place_max_level", "congestion_place_windows",
    "congestion_route_max_level", "congestion_route_windows",

    "max_route_layer", "place_blockage_frac",
    "power_mw", "power_switching_mw", "power_register_mw",
    "power_logic_mw", "power_clock_mw", "power_mode",
    "num_lut",
    "runtime_total_s", "wall_seconds",
    "sdc_sha1", "git_commit",
]

SUMMARY_FIELDS = [
    "bench", "class", "latency_preserving", "primary_metric", "tool",
    "variant", "mode", "stress_period_ns", "timing_status",

    "tns_reg2reg", "wns_reg2reg", "violating_paths",

    "num_ffs", "num_ffs_pre_syn",

    "cells", "area_um2", "wirelength_um", "power_mw", "compile_seconds",

    "route_share_pct", "overflow_route", "overflow_h_pct", "overflow_v_pct",
    "congestion_max_level", "achieved_density_pct",
]

def load_meta(benchmark_directory):
    return Benchmark(benchmark_directory).fields

def collect():
    rows = []
    for mj in sorted((ROOT / "results").rglob("metrics.json")):
        rel = mj.relative_to(ROOT / "results")
        if len(rel.parts) < 3:
            continue
        bench, tag = rel.parts[0], rel.parts[1]
        try:
            m = json.loads(mj.read_text())
        except json.JSONDecodeError:
            continue

        variant = tag.split("__")[0]
        period = None
        for piece in tag.replace("__", "_").split("_"):
            if piece.startswith("p") and piece[1:].replace(".", "").isdigit():
                period = piece[1:]
        m.setdefault("variant", variant)
        m.setdefault("mode", m.get("retime_mode", ""))
        gm = re.search(r"__genus_(\w+?)_p", tag)
        if gm:
            m["syn_mode"] = gm.group(1)
            if m.get("tool") == "innovus":
                m["mode"] = m["syn_mode"]
        if m.get("tool") == "innovus" and re.search(r"__innovus_.*(_ar|_m\d|_blk)", tag):
            m["tool"] = "innovus-nangate45-congested"
        if m.get("tool") == "vivado" and m.get("part"):
            ver = str(m.get("tool_version", "")).split("_")[0]
            stem = "vivado" if ver.startswith("2025.2") else f"vivado{ver}"
            dev = m["part"].split("-")[0]
            mm = re.match(r"^(xc7[a-z]\d+t)", dev)
            if mm:
                dev = mm.group(1)
            m["tool"] = f"{stem}-{dev}"
        elif m.get("tool") == "innovus":
            tech = os.environ.get("RT_PDK", "nangate45")
            m["tool"] = f"innovus-{tech}"
            if re.search(r"__innovus_.*(_ar|_m\d|_blk)", tag):
                m["tool"] += "-congested"
        prov = mj.parent / "provenance.json"
        if prov.exists():
            try:
                pv = json.loads(prov.read_text())
                m["sdc_sha1"] = pv.get("sdc_sha1", "")
                m["git_commit"] = pv.get("git_commit", "")
            except json.JSONDecodeError:
                pass
        m["period_ns"] = period or m.get("clock_period_ns")
        m["bench"] = bench
        meta = load_meta(ROOT / "benchmarks" / bench)
        m["class"] = meta.get("class", "")
        m["_meta"] = meta
        m["_tag"] = tag
        rows.append(m)
    return rows

def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None

def main():
    rows = collect()
    if not rows:
        print("no results found")
        return 1

    outdir = ROOT / "results"
    with (outdir / "results.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=RUN_FIELDS, extrasaction="ignore")
        w.writeheader()
        for r in sorted(rows, key=lambda x: (x["bench"], x.get("tool", ""),
                                             x.get("variant", ""),
                                             str(x.get("mode", "")),
                                             num(x.get("period_ns")) or 0)):
            w.writerow(r)

    stress = {}
    for sf in ("results/stress_wns.json", "results/stress_wns_new.json"):
        sp = ROOT / sf
        if not sp.exists():
            continue
        try:
            for r in json.loads(sp.read_text()):
                if r.get("stressed") and r.get("tns") is not None:
                    stress[(r["bench"], r["variant"], r["mode"])] = r
        except (json.JSONDecodeError, KeyError):
            pass

    groups = defaultdict(list)
    for r in rows:
        if str(r.get("tool", "")).startswith("innovus"):
            key = (r["bench"], r.get("tool", "innovus"), r.get("variant", ""),
                   r.get("syn_mode") or "pnr")
        else:
            key = (r["bench"], r.get("tool", "?"), r.get("variant", ""),
                   str(r.get("mode", "")))
        groups[key].append(r)

    skipped = []
    with (outdir / "summary.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=SUMMARY_FIELDS, extrasaction="ignore")
        w.writeheader()
        for (bench, tool, variant, mode), rs in sorted(groups.items()):
            meta = rs[0].get("_meta", {})
            st = (stress.get((bench, variant, mode)) or {}) \
                if tool == "innovus-nangate45" else {}

            def is_routed(r):
                return (r.get("routed_wirelength_um") is not None
                        or r.get("impl_wns_ns") is not None)

            def routed_at(period):
                best = None
                for r in rs:
                    if not is_routed(r):
                        continue
                    pv = num(r.get("period_ns"))
                    if period is None or pv is None:
                        continue
                    if abs(pv - period) < 5e-3:
                        best = r
                return best

            ref = routed_at(st.get("period"))
            if ref is None:
                ref = next((r for r in rs if is_routed(r)), None)
            if ref is None:
                skipped.append((bench, tool, variant, mode))
                continue

            ovf = ref.get("overflow_route")
            w.writerow({
                "bench": bench,
                "class": meta.get("class", ""),
                "latency_preserving": meta.get("latency_preserving", ""),
                "primary_metric": meta.get("primary_metric", ""),
                "tool": tool,
                "variant": variant,
                "mode": mode,
                "stress_period_ns": st.get("period", num(ref.get("period_ns")) or ""),
                "timing_status": ref.get("postroute_timing_status",
                                         ref.get("timing_status", "")),
                "tns_reg2reg": st.get("tns", ref.get("postroute_tns_reg2reg",
                                                     ref.get("impl_tns_ns", ""))),
                "wns_reg2reg": st.get("wns", ref.get("postroute_wns_reg2reg",
                                                     ref.get("wns_reg2reg_ns", ""))),
                "violating_paths": st.get("viol",
                                          ref.get("postroute_violating_reg2reg", "")),
                "num_ffs": (ref.get("num_ffs") or ref.get("num_seq")
                            or ref.get("num_ff", "")),
                "num_ffs_pre_syn": (ref.get("num_ffs_pre_syn")
                                    or ref.get("num_seq_pre_syn", "")),
                "cells": ref.get("num_cells") or ref.get("num_lut", ""),
                "area_um2": ref.get("area_um2", ""),
                "wirelength_um": ref.get("routed_wirelength_um", ""),
                "power_mw": ref.get("power_mw", ""),
                "compile_seconds": ref.get("wall_seconds", ""),
                "route_share_pct": ref.get("path_route_share_pct", ""),
                "overflow_route": ovf if ovf is not None else "",
                "overflow_h_pct": ref.get("overflow_route_h_pct", ""),
                "overflow_v_pct": ref.get("overflow_route_v_pct", ""),
                "congestion_max_level": max(
                    [v for v in (ref.get("congestion_place_max_level"),
                                 ref.get("congestion_route_max_level"))
                     if isinstance(v, (int, float))] or [""]) or "",
                "achieved_density_pct": ref.get("achieved_density_pct", ""),
            })

    print(f"wrote {outdir/'results.csv'} ({len(rows)} runs)")
    print(f"wrote {outdir/'summary.csv'} "
          f"({len(groups) - len(skipped)} routed configs, "
          f"{len(skipped)} unrouted configs dropped)")
    by_tool = {}
    for b, t, v, m in skipped:
        by_tool[t] = by_tool.get(t, 0) + 1
    if by_tool:
        print("  dropped by tool: " + ", ".join(f"{k}={v}" for k, v in
                                                sorted(by_tool.items())))
    return 0

if __name__ == "__main__":
    sys.exit(main())
