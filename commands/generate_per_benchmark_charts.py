#!/usr/bin/env python3
"""One SVG per benchmark: reg2reg TNS by tool and by variant.

TNS is plotted as MAGNITUDE with the axis labelled "closer to zero is better", because
TNS is always <= 0 and a bar chart of negative numbers reads backwards -- a longer bar
would mean worse while looking like more.

Missing data is drawn, not silently omitted: a config with no post-route run gets a
hollow marker on the zero line and is listed under the chart. Roughly a third of the
matrix is still unmeasured after the registered-I/O change invalidated every earlier
ASIC number, and a plot that quietly dropped those would imply a completeness the data
does not have.
"""

from pathlib import Path
import sys

import collections
import csv

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "per_bench"

TOOL_ORDER = ["innovus-nangate45", "vivado-xc7a100t", "vivado-xcau7p",
              "vivado-xcau15p", "innovus-nangate45-congested"]

COLORS = {"orig/off": "#2a78d6", "orig/on": "#eb6834",
          "directive/off": "#9b5cc4", "retimed/off": "#2e9e6b"}
LABEL = {"orig/off": "original (no retiming)", "orig/on": "tool retiming",
         "directive/off": "directive only", "retimed/off": "manual (hand-retimed)"}
SHORT = {"orig/off": "orig", "orig/on": "tool", "directive/off": "direct",
         "retimed/off": "manual"}
INK, MUTED, GRID, SURF = "#1a1a19", "#6b6b68", "#e6e6e3", "#fcfcfb"

def main():
    miss = {}
    mp = ROOT / "results" / "missing.csv"
    if mp.exists():
        for r in csv.DictReader(mp.open()):
            miss[(r["bench"], r["tool"], r["variant"], r["mode"])] = r["status"]

    rows = list(csv.DictReader((ROOT / "results" / "summary.csv").open()))
    data = collections.defaultdict(dict)
    tools = collections.OrderedDict()
    for r in rows:
        key = f"{r['variant']}/{r['mode']}"
        if key not in COLORS:
            continue
        if r["tool"].startswith("vivado2023.1"):
            continue
        tools[r["tool"]] = True
        try:
            v = float(r["tns_reg2reg"])
        except (TypeError, ValueError):
            v = None
        data[r["bench"]][(r["tool"], key)] = v
    tools = list(tools)

    OUT.mkdir(parents=True, exist_ok=True)
    made, gaps = [], []
    for bench in sorted(data):
        d = data[bench]
        present = [t for t in TOOL_ORDER if t in tools] or list(tools)
        absent = []
        if not present:
            gaps.append((bench, "no data at all"))
            continue
        missing = [f"{t}:{k.split('/')[0]}" for t in present for k in COLORS
                   if (t, k) not in d or d[(t, k)] is None]

        fig, axes = plt.subplots(1, len(present), figsize=(1.55 * len(present) + 0.9, 3.9),
                                 facecolor=SURF, squeeze=False)
        axes = axes[0]
        w = 0.19
        for j, t in enumerate(present):
            ax = axes[j]
            ax.set_facecolor(SURF)
            empty = all(d.get((t, k)) is None for k in COLORS)
            for i, key in enumerate(COLORS):
                x = i
                v = d.get((t, key))
                if v is None:
                    if empty:
                        continue      # the panel carries one message instead

                    st = miss.get((bench, t, *key.split("/")), "PENDING_RUN")
                    if st.startswith("FAILED"):
                        ax.plot([x], [0], marker="x", ms=7, mew=2.0,
                                color="#c0392b", zorder=3)
                    else:
                        ax.plot([x], [0], marker="o", ms=6, mfc="none",
                                mec=MUTED, mew=1.2, zorder=3)
                    continue
                ax.bar([x], [abs(v)], width=0.68, color=COLORS[key], zorder=2)
            ax.set_xticks(range(len(COLORS)))
            ax.set_xticklabels([SHORT[k] for k in COLORS], fontsize=7.5,
                               color=MUTED, rotation=45, ha="right")
            ax.set_xlim(-0.6, len(COLORS) - 0.4)
            ax.set_title(t.replace("innovus-", "").replace("vivado-", "viv ")
                          .replace("vivado2023.1-", "viv23 ")
                          .replace("nangate45", "n45"),
                         fontsize=8.5, color=INK, pad=6)
            if j == 0:
                ax.set_ylabel("|reg2reg TNS| (ns)", fontsize=9.5, color=INK)
            if empty:
                sts = {miss.get((bench, t, *k.split("/")), "PENDING_RUN")
                       for k in COLORS}
                blocked = sorted(x for x in sts if x.startswith("FAILED"))
                msg = "pending a run"
                if blocked:
                    b0 = blocked[0]
                    n = "".join(c for c in b0 if c.isdigit())
                    msg = f"blocked:\n{n} I/O ports" if n else "blocked:\nneeds a fix"
                ax.text(0.5, 0.5, msg, transform=ax.transAxes, ha="center",
                        va="center", fontsize=8, color="#c0392b" if blocked else MUTED,
                        wrap=True)
                ax.set_yticks([])
            ax.grid(axis="y", color=GRID, lw=0.8)
            ax.set_axisbelow(True)
            for sp in ("top", "right"):
                ax.spines[sp].set_visible(False)
            for sp in ("left", "bottom"):
                ax.spines[sp].set_color(GRID)
            ax.tick_params(colors=MUTED, length=0, labelsize=8)
        fig.suptitle(bench.replace("_", " "), fontsize=11, fontweight="bold",
                     color=INK, x=0.01, ha="left", y=0.995)
        fig.text(0.01, 0.93, "|reg2reg TNS| — shorter is better; each panel has its "
                 "own scale", fontsize=7.5, color=MUTED, ha="left")
        ax = axes[-1]
        handles = [Line2D([], [], color=c, lw=7, label=LABEL[k])
                   for k, c in COLORS.items()]
        if missing:
            handles.append(Line2D([], [], marker="o", ls="none", mfc="none",
                                  mec=MUTED, label="pending a future run"))
            if any(miss.get((bench, t, *k.split("/")), "").startswith("FAILED")
                   for t in present for k in COLORS):
                handles.append(Line2D([], [], marker="x", ls="none", color="#c0392b",
                                      label="blocked: needs a fix"))
        fig.legend(handles=handles, loc="lower center", bbox_to_anchor=(0.5, 0.035),
                   ncol=min(len(handles), 6), frameon=False, fontsize=7.5)
        if missing:
            n = len(set(missing))
            fig.text(0.5, 0.002, f"{n} config(s) unmeasured — see results/missing.csv",
                     ha="center", fontsize=6.5, color=MUTED)
            gaps.append((bench, f"{n} config(s) unmeasured"))
        fig.tight_layout(rect=[0, 0.14, 1, 0.92])
        f = OUT / f"{bench}.svg"
        fig.savefig(f, format="svg", facecolor=SURF, bbox_inches="tight")
        plt.close(fig)
        made.append(bench)

    print(f"wrote {len(made)} SVGs to {OUT}")
    print(f"\n{'benchmark':<34}status")
    allb = sorted(x.name for x in (ROOT / "benchmarks").iterdir()
                  if (x / "variants" / "orig").is_dir())
    gd = dict(gaps)
    for b in allb:
        if b not in data:
            print(f"  {b:<32}NO DATA (never routed)")
        elif b in gd:
            print(f"  {b:<32}{gd[b]}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
