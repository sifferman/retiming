#!/usr/bin/env python3
"""Python port of the dataviz skill's palette validator (scripts/validate_palette.js).

Ported because this machine has no node runtime and the skill is explicit that the
colour checks must be computed, not eyeballed. Thresholds, the Machado-Oliveira-
Fernandes (2009) severity-1.0 CVD matrices, and the OKLab conversion are copied
verbatim from the JS so the two agree.

usage: validate_palette.py "#hex,#hex,..." [--mode light|dark] [--pairs adjacent|all]
"""

import sys

import argparse
import itertools
import math

BAND = {"light": (0.43, 0.77), "dark": (0.48, 0.67)}   # OKLCH L
CHROMA_FLOOR = 0.10
CVD_TARGET, CVD_FLOOR = 8.0, 6.0
NORMAL_FLOOR = 15.0
CONTRAST_MIN = 3.0
DEFAULT_SURFACE = {"light": "#fcfcfb", "dark": "#1a1a19"}

MACHADO = {
    "protan": [[0.152286, 1.052583, -0.204868],
               [0.114503, 0.786281, 0.099216],
               [-0.003882, -0.048116, 1.051998]],
    "deutan": [[0.367322, 0.860646, -0.227968],
               [0.280085, 0.672501, 0.047413],
               [-0.011820, 0.042940, 0.968881]],
    "tritan": [[1.255528, -0.076749, -0.178779],
               [-0.078411, 0.930809, 0.147602],
               [0.004733, 0.691367, 0.303900]],
}

def hex2srgb(h):
    h = h.strip().lstrip("#")
    return [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]

def s2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def convert_srgb_channel_to_linear(h):
    return [s2lin(c) for c in hex2srgb(h)]

def compute_relative_luminance(h):
    r, g, b = convert_srgb_channel_to_linear(h)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def compute_contrast_ratio(a, b):
    hi, lo = sorted([compute_relative_luminance(a), compute_relative_luminance(b)], reverse=True)
    return (hi + 0.05) / (lo + 0.05)

def convert_linear_rgb_to_oklab(rgb):
    r, g, b = rgb
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]

def convert_hex_to_oklch(h):
    L, a, b = convert_linear_rgb_to_oklab(convert_srgb_channel_to_linear(h))
    return L, math.hypot(a, b)

def simulate(h, kind):
    r, g, b = convert_srgb_channel_to_linear(h)
    M = MACHADO[kind]
    return [min(1.0, max(0.0, M[i][0] * r + M[i][1] * g + M[i][2] * b)) for i in range(3)]

def compute_color_difference(h1, h2, kind=None):
    a = convert_linear_rgb_to_oklab(simulate(h1, kind) if kind else convert_srgb_channel_to_linear(h1))
    b = convert_linear_rgb_to_oklab(simulate(h2, kind) if kind else convert_srgb_channel_to_linear(h2))
    return 100 * math.dist(a, b)

def validate(palette, mode="light", surface=None, pairs="adjacent"):
    surface = surface or DEFAULT_SURFACE[mode]
    lo, hi = BAND[mode]
    report, ok = [], True

    off = [(c, round(convert_hex_to_oklch(c)[0], 3)) for c in palette
           if not (lo <= convert_hex_to_oklch(c)[0] <= hi)]
    ok &= not off
    report.append(("Lightness band", "PASS" if not off else "FAIL",
                   f"outside band: {off}" if off else
                   f"all {len(palette)} inside L {lo}-{hi}"))

    lowc = [(c, round(convert_hex_to_oklch(c)[1], 3)) for c in palette if convert_hex_to_oklch(c)[1] < CHROMA_FLOOR]
    ok &= not lowc
    report.append(("Chroma floor", "PASS" if not lowc else "FAIL",
                   f"reads gray: {lowc}" if lowc else
                   f"all {len(palette)} >= {CHROMA_FLOOR}"))

    idx = list(range(len(palette)))
    pl = (list(itertools.combinations(idx, 2)) if pairs == "all"
          else [(i, i + 1) for i in idx[:-1]])
    if pl:
        worst = min(min(compute_color_difference(palette[i], palette[j], "protan"),
                        compute_color_difference(palette[i], palette[j], "deutan")) for i, j in pl)
        tri = min(compute_color_difference(palette[i], palette[j], "tritan") for i, j in pl)
        state = "PASS" if worst >= CVD_TARGET else ("FLOOR" if worst >= CVD_FLOOR else "FAIL")
        ok &= state != "FAIL"
        report.append((f"CVD separation ({pairs})", state,
                       f"worst protan/deutan dE {worst:.1f} (target >={CVD_TARGET}, "
                       f"floor {CVD_FLOOR}); tritan {tri:.1f}"))

        nworst = min(compute_color_difference(palette[i], palette[j]) for i, j in pl)
        nok = nworst >= NORMAL_FLOOR
        ok &= nok
        report.append(("Normal-vision floor", "PASS" if nok else "FAIL",
                       f"worst pair dE {nworst:.1f} (floor {NORMAL_FLOOR})"))
    else:
        report.append(("CVD separation", "PASS", "single series, no pairs"))

    low = [(c, round(compute_contrast_ratio(c, surface), 2)) for c in palette
           if compute_contrast_ratio(c, surface) < CONTRAST_MIN]
    report.append(("Contrast vs surface", "PASS" if not low else "RELIEF",
                   f"sub-3:1 (needs visible labels or table view): {low}" if low
                   else f"all >= {CONTRAST_MIN}:1 vs {surface}"))
    return ok, report

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("palette")
    ap.add_argument("--mode", default="light", choices=["light", "dark"])
    ap.add_argument("--pairs", default="adjacent", choices=["adjacent", "all"])
    ap.add_argument("--surface", default=None)
    a = ap.parse_args()
    pal = [c.strip() for c in a.palette.split(",") if c.strip()]
    ok, rep = validate(pal, a.mode, a.surface, a.pairs)
    print(f"palette: {' '.join(pal)}   mode={a.mode}  pairs={a.pairs}")
    for name, state, detail in rep:
        print(f"  {state:<7} {name:<28} {detail}")
    print("RESULT:", "OK" if ok else "PROBLEMS")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
