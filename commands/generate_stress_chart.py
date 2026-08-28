#!/usr/bin/env python3
"""Forest plot of TNS change at a stress period -- the metric that actually separates.

Why this is a separate script from plot_improvements.py: that one compares configs at
a period every config MET, and these runs all VIOLATE on purpose.  Pooling the two
would compare a design that closed with one that did not.

Fmax could not do this job.  Across 52 routed configs at feasible periods the reg2reg
WNS sat at ~0.000 for nearly all of them, because Genus and Innovus both stop the
moment they meet -- so Fmax reported the constraint.  Constrain below what the fastest
config can reach and every tool runs at maximum effort, and TNS then separates variants
by factors rather than percent (r30: -110.8 -> -294.5 with retiming on).
"""

from pathlib import Path
import sys

import json
import statistics as st

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent
BLUE, ORANGE = "#2a78d6", "#eb6834"
INK, MUTED, GRID, SURF = "#1a1a19", "#6b6b68", "#e6e6e3", "#ffffff"

def load():
    rows = {}
    for f in ("results/stress_wns.json", "results/stress_wns_new.json"):
        p = ROOT / f
        if not p.exists():
            continue
        for r in json.loads(p.read_text()):
            if r.get("stressed") and r.get("tns") is not None:
                rows[(r["bench"], r["variant"], r["mode"])] = r
    return rows

def main():
    rows = load()
    benches = sorted({k[0] for k in rows})
    data = []
    for b in benches:
        base = rows.get((b, "orig", "off"))
        if not base or not base.get("tns"):
            continue
        for lab, key in (("auto", (b, "orig", "on")), ("manual", (b, "retimed", "off"))):
            r = rows.get(key)
            if not r or r.get("tns") is None:
                continue
            imp = 100.0 * (abs(base["tns"]) - abs(r["tns"])) / abs(base["tns"])
            data.append((b, lab, imp))
    if not data:
        print("no stressed results yet")
        return 1

    order = sorted({d[0] for d in data})
    fig, ax = plt.subplots(figsize=(11, 0.42 * len(order) + 2.4), facecolor=SURF)
    ax.set_facecolor(SURF)
    for i, b in enumerate(order):
        y = len(order) - i
        for lab, col, off, mk in (("auto", BLUE, 0.16, "o"), ("manual", ORANGE, -0.16, "s")):
            vals = [d[2] for d in data if d[0] == b and d[1] == lab]
            if not vals:
                continue
            v = st.median(vals)
            ax.plot([0, v], [y + off] * 2, color=col, lw=2.4, solid_capstyle="round",
                    zorder=2)
            ax.plot([v], [y + off], mk, color=col, ms=8, mec=SURF, mew=1.6, zorder=3)
            ax.annotate(f"{v:+.0f}%", (v, y + off), textcoords="offset points",
                        xytext=(10 if v >= 0 else -10, 0), ha="left" if v >= 0 else "right",
                        va="center", fontsize=8.5, color=MUTED)
    ax.axvline(0, color=INK, lw=1.1, zorder=1)
    ax.set_yticks(range(1, len(order) + 1))
    ax.set_yticklabels([b.replace("_", " ") for b in reversed(order)], fontsize=9,
                       color=INK)
    ax.set_xlabel("% reduction in reg2reg TNS at a period no config can meet"
                  "   —   right of the line is better", fontsize=9.5, color=INK)
    ax.set_title("Retiming benefit measured under maximum optimisation pressure",
                 fontsize=13, fontweight="bold", color=INK, loc="left", pad=14)
    ax.grid(axis="x", color=GRID, lw=0.8)
    ax.set_axisbelow(True)
    for sp in ("top", "right", "left"):
        ax.spines[sp].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.tick_params(colors=MUTED, length=0)
    from matplotlib.lines import Line2D
    ax.legend(handles=[Line2D([], [], color=BLUE, marker="o", lw=2.4, ms=8,
                              label="Tool-automatic retiming"),
                       Line2D([], [], color=ORANGE, marker="s", lw=2.4, ms=8,
                              label="Manual (hand-retimed RTL)")],
              loc="lower right", frameon=False, fontsize=9)
    fig.tight_layout()
    out = ROOT / "docs" / "stress_tns_light.svg"
    fig.savefig(out, format="svg", facecolor=SURF)
    print(f"wrote {out}  ({len(order)} benchmarks)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
