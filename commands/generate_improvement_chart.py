#!/usr/bin/env python3
"""Forest plot of % improvement over the no-retiming baseline, per tool and metric,
for manual (hand-retimed RTL) vs tool-automatic retiming.

Why a forest plot rather than bars
----------------------------------
Each point is a median over 18-19 benchmarks whose spread is huge: Genus Fmax under
tool-automatic retiming ranges from 0% to +117%, and the manual cell-count
distribution has an outlier at -265%. A bar shows only the median and silently
throws all of that away. A forest plot shows the point estimate, the interquartile
range, and the full range on the same row, so a wide or skewed distribution cannot
be mistaken for a firm result.

Marks: circle = tool-automatic, square = manual, so the two series are separable by
shape as well as hue (composite encoding, which survives colour-vision deficiency
and greyscale printing). Marker area scales with n. The thick line is the IQR, the
thin line the full range; a range extending past the axis is drawn with an
arrowhead rather than silently clipped.

Colour: two categorical slots from the validated default palette, checked with
commands/validate_color_palette.py -- all six checks pass in both modes.
"""

from pathlib import Path
import sys

import argparse
import json

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Rectangle

ROOT = Path(__file__).resolve().parent.parent

THEME = {
    "light": dict(surface="#fcfcfb", band="#f4f3ef", text="#0b0b0b",
                  text2="#52514e", muted="#8d8c85", grid="#e6e5e0",
                  rule="#b9b8b1", s_auto="#2a78d6", s_manual="#eb6834"),
    "dark": dict(surface="#1a1a19", band="#232320", text="#ffffff",
                 text2="#c3c2b7", muted="#8d8c85", grid="#34332f",
                 rule="#54534d", s_auto="#3987e5", s_manual="#d95926"),
}

ORDER = ["genus", "innovus", "vivado", "yosys", "openroad_syn"]

EXCLUDE = {"openroad_syn"}
MIN_N = 3
ROW_PX = 30.0        # vertical space per estimate row
DPI = 100.0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="light", choices=["light", "dark"])
    ap.add_argument("--out", default=None)
    ap.add_argument("--interval", default="iqr", choices=["iqr", "range"],
                    help="which spread the thick line shows")
    args = ap.parse_args()
    T = THEME[args.mode]

    data = json.loads((ROOT / "results" / "improvements.json").read_text())
    tools = ([t for t in ORDER if t in data and t not in EXCLUDE]
             + [t for t in data if t not in ORDER and t not in EXCLUDE])
    if not tools:
        print("no data in results/improvements.json"); return 1

    rows = []          # (kind, payload)
    for t in tools:
        e = data[t]
        rows.append(("header", (t, e)))
        for k, d in e["metrics"].items():
            if not any(d.get(s2) for s2 in ("auto", "manual")):
                continue
            rows.append(("metric", (t, k, d)))
        rows.append(("spacer", None))
    if rows and rows[-1][0] == "spacer":
        rows.pop()

    n_rows = len(rows)
    fig_h = (n_rows * ROW_PX) / DPI + 1.85
    fig = plt.figure(figsize=(11.4, fig_h), dpi=DPI)
    fig.patch.set_facecolor(T["surface"])
    gs = fig.add_gridspec(1, 2, width_ratios=[1.0, 0.40], wspace=0.02,
                          left=0.175, right=0.985,
                          top=1 - 1.30 / fig_h, bottom=0.62 / fig_h)
    ax = fig.add_subplot(gs[0, 0])
    axt = fig.add_subplot(gs[0, 1], sharey=ax)

    for a in (ax, axt):
        a.set_facecolor(T["surface"])
        for sp in a.spines.values():
            sp.set_visible(False)

    qs = [v for _, p in rows if _ == "metric"
          for s in ("auto", "manual") if (d := p[2].get(s)) and d["n"] >= MIN_N
          for v in (d["q1"], d["q3"], d["median"])]
    if not qs:
        qs = [0.0]
    lo, hi = min(qs + [0.0]), max(qs + [0.0])
    pad = max(12.0, (hi - lo) * 0.14)
    xlo, xhi = lo - pad, hi + pad

    y_of = {}
    for i, (kind, payload) in enumerate(rows):
        y_of[i] = n_rows - 1 - i

    off = 0.21
    labels_left = []

    for i, (kind, payload) in enumerate(rows):
        y = y_of[i]
        if kind == "spacer":
            labels_left.append((y, "", False))
            continue
        if kind == "header":
            t, e = payload
            labels_left.append((y, e["label"].replace("\n", " — "), True))
            ax.axhline(y - 0.5, color=T["rule"], linewidth=0.9, zorder=1)
            if not any(d.get(s) and d[s]["n"] >= MIN_N
                       for d in e["metrics"].values() for s in ("auto", "manual")):
                note = (e.get("no_auto_reason") or "sweep still running").replace("\n", " ")
                ax.text(0.5, y - 3.0, f"no comparable data yet — {note}",
                        transform=ax.get_yaxis_transform(which="grid"),
                        ha="center", va="center", fontsize=9,
                        color=T["muted"], style="italic", zorder=4)
            continue

        t, k, d = payload
        labels_left.append((y, d["label"], False))

        if i % 2 == 0:
            ax.add_patch(Rectangle((xlo, y - 0.5), xhi - xlo, 1.0, facecolor=T["band"],
                                   edgecolor="none", zorder=0))
            axt.add_patch(Rectangle((0, y - 0.5), 1, 1.0, facecolor=T["band"],
                                    edgecolor="none", zorder=0,
                                    transform=axt.get_yaxis_transform(which="grid")))

        for name, color, marker in (("auto", T["s_auto"], "o"),
                                    ("manual", T["s_manual"], "s")):
            dd = d.get(name)
            yy = y + (off if name == "auto" else -off)
            if not dd:
                continue
            if dd["n"] < MIN_N:
                ax.text(xlo + pad * 0.12, yy, f"n={dd['n']} — too few to summarise",
                        va="center", ha="left", fontsize=7.4, color=T["muted"],
                        style="italic", zorder=4)
                continue

            med, q1, q3 = dd["median"], dd["q1"], dd["q3"]
            mn, mx = dd["min"], dd["max"]
            thick = (q1, q3) if args.interval == "iqr" else (mn, mx)

            a0, a1 = max(mn, xlo), min(mx, xhi)
            if a1 > a0:
                ax.plot([a0, a1], [yy, yy], color=color, linewidth=1.0,
                        alpha=0.55, solid_capstyle="butt", zorder=3)
            for bound, lim, dx in ((mn, xlo, -1), (mx, xhi, +1)):
                if (bound < xlo and dx < 0) or (bound > xhi and dx > 0):
                    ax.annotate("", xy=(lim + dx * pad * 0.055, yy),
                                xytext=(lim + dx * pad * 0.20, yy),
                                arrowprops=dict(arrowstyle="-|>", color=color,
                                                lw=1.0, alpha=0.75,
                                                shrinkA=0, shrinkB=0), zorder=3)

            ax.plot([max(thick[0], xlo), min(thick[1], xhi)], [yy, yy],
                    color=color, linewidth=3.2, solid_capstyle="round", zorder=4)

            ms = 6.0 + 4.0 * (dd["n"] / 20.0) ** 0.5
            ax.plot([med], [yy], marker=marker, markersize=ms, color=color,
                    markeredgecolor=T["surface"], markeredgewidth=2.0,
                    linestyle="none", zorder=5)

    ax.set_xlim(xlo, xhi)
    ax.set_ylim(-0.6, n_rows - 0.4)
    ax.set_yticks([y for y, _, _ in labels_left])
    ax.set_yticklabels(["" for _ in labels_left])
    ax.grid(axis="x", color=T["grid"], linewidth=0.8, linestyle="-", zorder=0)
    ax.set_axisbelow(False)
    ax.axvline(0, color=T["text2"], linewidth=1.2, zorder=2)
    ax.tick_params(axis="x", length=0, colors=T["text2"], labelsize=9)
    ax.tick_params(axis="y", length=0)

    for y, txt, is_header in labels_left:
        if not txt:
            continue
        if is_header:
            ax.text(-0.168, y, txt, transform=ax.get_yaxis_transform(),
                    ha="left", va="center", fontsize=10.6,
                    color=T["text"], fontweight="bold")
        else:
            ax.text(-0.012, y, txt, transform=ax.get_yaxis_transform(),
                    ha="right", va="center", fontsize=9.2,
                    color=T["text2"])

    axt.set_xlim(0, 1)
    axt.set_xticks([])
    axt.tick_params(axis="y", length=0)
    axt.set_yticklabels([])
    axt.text(0.02, n_rows - 0.05, "median  [IQR]", ha="left", va="center",
             fontsize=8.4, color=T["muted"], fontweight="bold")
    axt.text(0.86, n_rows - 0.05, "n", ha="right", va="center",
             fontsize=8.4, color=T["muted"], fontweight="bold")

    for i, (kind, payload) in enumerate(rows):
        if kind != "metric":
            continue
        y = y_of[i]
        _, _, d = payload
        for name in ("auto", "manual"):
            dd = d.get(name)
            if not dd or dd["n"] < MIN_N:
                continue
            yy = y + (off if name == "auto" else -off)
            def sg(v):
                return "0" if abs(v) < 0.5 else f"{v:+.0f}"
            axt.text(0.02, yy,
                     f"{sg(dd['median'])}%  [{sg(dd['q1'])}, {sg(dd['q3'])}]",
                     ha="left", va="center", fontsize=8.0, color=T["text2"])
            axt.text(0.86, yy, str(dd["n"]), ha="right", va="center",
                     fontsize=8.0, color=T["muted"])

    ax.set_xlabel("% improvement vs the no-retiming baseline "
                  "(original RTL, tool retiming off)  —  right of the line is better",
                  fontsize=9, color=T["text2"], labelpad=9)

    handles = [
        Line2D([0], [0], marker="o", color=T["s_auto"], markersize=8,
               markeredgecolor=T["surface"], markeredgewidth=2, lw=3.2,
               label="Tool-automatic retiming"),
        Line2D([0], [0], marker="s", color=T["s_manual"], markersize=8,
               markeredgecolor=T["surface"], markeredgewidth=2, lw=3.2,
               label="Manual (hand-retimed RTL)"),
    ]
    fig.legend(handles=handles, loc="upper left",
               bbox_to_anchor=(0.175, 1 - 0.86 / fig_h), ncol=2, frameon=False,
               fontsize=9.5, labelcolor=T["text2"], handlelength=2.4,
               columnspacing=2.2, borderaxespad=0)

    fig.text(0.175, 1 - 0.24 / fig_h, "Retiming benefit by tool and metric",
             ha="left", va="top", fontsize=14.5, color=T["text"], fontweight="bold")
    fig.text(0.175, 1 - 0.47 / fig_h,
             "Point = median across benchmarks; thick line = interquartile range; "
             "thin line = full range (arrow = extends past the axis).\n"
             "Fmax at each config's tightest met period, lower-bounded ones excluded; "
             "other metrics at the tightest period every config met.\n"
             "OpenROAD syn is omitted: it has no retiming, so there is no "
             "tool-automatic series to compare against.",
             ha="left", va="top", fontsize=8.4, color=T["muted"])

    out = Path(args.out or (ROOT / "docs" / f"improvements_{args.mode}.svg"))
    out.parent.mkdir(parents=True, exist_ok=True)
    fmt = out.suffix.lstrip(".").lower() or "svg"
    fig.savefig(out, format=fmt, facecolor=T["surface"],
                dpi=150 if fmt == "png" else None)
    print(f"wrote {out}  ({n_rows} rows, interval={args.interval})")
    return 0

if __name__ == "__main__":
    sys.exit(main())
