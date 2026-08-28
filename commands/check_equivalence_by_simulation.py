#!/usr/bin/env python3
"""Strict-retiming equivalence check between two variants of a benchmark.

Method: compile each variant against the *same* generated testbench, run both with
identical deterministic stimulus, and diff the per-cycle output traces.

Because both variants expose the same module name and port list, no renaming or
miter construction is needed -- two independent simulations plus a diff is enough,
and it works for arbitrary internal hierarchy.

This is a bounded check, not a proof.  `commands/check_logical_equivalence.sh` runs Cadence
Conformal for the formal argument.  The bounded check is the one that runs on
every commit, and it is deliberately reset-heavy: the generated testbench pulses
reset mid-run, which is what catches an incorrect retimed reset value.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from benchmark_lib.benchmark import Benchmark
from benchmark_lib.systemverilog_module import parse_module

import argparse
import os
import re
import subprocess
import tempfile

IVERILOG = os.environ.get("IVERILOG_BIN",
                          str(Path.home() / "Utils/oss-cad-suite/bin/iverilog"))
VVP = os.environ.get("VVP_BIN", str(Path.home() / "Utils/oss-cad-suite/bin/vvp"))

def load_meta(benchmark_directory):
    return Benchmark(benchmark_directory).fields

def sv_files(d: Path):
    return sorted(str(p) for p in d.glob("*.sv")) + \
           sorted(str(p) for p in d.glob("*.v"))

def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)

def simulate(top, tb, srcs, workdir, tag, cycles, vcd=None):
    vvp_out = workdir / f"{tag}.vvp"
    trace = workdir / f"{tag}.trace"
    cmd = [IVERILOG, "-g2012", "-o", str(vvp_out), "-s", f"tb_{top}", tb] + srcs
    r = run(cmd)
    if r.returncode != 0:
        print(f"  [{tag}] COMPILE FAILED\n{r.stdout}\n{r.stderr}")
        return None
    args = [VVP, str(vvp_out), f"+trace={trace}", f"+cycles={cycles}"]
    if vcd:
        args.append(f"+vcd={vcd}")
    r = run(args)
    if not trace.exists():
        print(f"  [{tag}] SIM PRODUCED NO TRACE\n{r.stdout}\n{r.stderr}")
        return None
    return trace

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bench", help="benchmark directory")
    ap.add_argument("--a", default="orig")
    ap.add_argument("--b", default="retimed")
    ap.add_argument("--cycles", type=int, default=4000)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--settle", type=int, default=3,
                    help="extra cycles masked after each reset release when "
                         "--skew is used, to let pipelines of differing depth refill")
    ap.add_argument("--skew", type=int, default=0,
                    help="cycles that variant B lags variant A. Nonzero means the "
                         "pair is NOT a strict retiming; only use it for "
                         "benchmarks declared LATENCY-CHANGING.")
    args = ap.parse_args()

    bench = Path(args.bench).resolve()
    va, vb = bench / "variants" / args.a, bench / "variants" / args.b
    for v in (va, vb):
        if not v.is_dir():
            raise SystemExit(f"check_equiv: missing variant dir {v}")

    srcs_a, srcs_b = sv_files(va), sv_files(vb)
    if not srcs_a or not srcs_b:
        raise SystemExit("check_equiv: no sources found")

    from benchmeta import top_of
    top = top_of(bench, srcs_a[0])

    top_src = next((c for c in srcs_a
                    if re.search(rf"\bmodule\s+{top}\b", Path(c).read_text())),
                   srcs_a[0])

    tmp = Path(tempfile.mkdtemp(prefix=f"equiv_{bench.name}_"))
    tb = tmp / f"tb_{top}.sv"
    gen = run([sys.executable, str(Path(__file__).parent / "gen_tb.py"),
               top_src, "--top", top, "--out", str(tb),
               "--cycles", str(args.cycles)])
    if gen.returncode != 0:
        raise SystemExit(f"check_equiv: gen_tb failed\n{gen.stdout}{gen.stderr}")

    print(f"== {bench.name}: {args.a} vs {args.b}  (top={top}, {args.cycles} cycles)")
    ta = simulate(top, str(tb), srcs_a, tmp, args.a, args.cycles)
    tb_tr = simulate(top, str(tb), srcs_b, tmp, args.b, args.cycles)
    if ta is None or tb_tr is None:
        print("RESULT: ERROR")
        return 2

    la, lb = ta.read_text().splitlines(), tb_tr.read_text().splitlines()
    if len(la) != len(lb):
        print(f"RESULT: FAIL (trace length {len(la)} vs {len(lb)})")
        return 1

    def split(lines):
        rst, outs = [], []
        for ln in lines:
            f = ln.split()
            rst.append(f[1] if len(f) > 1 else "-")
            outs.append(" ".join(f[2:]))
        return rst, outs

    rst_a, out_a = split(la)
    rst_b, out_b = split(lb)

    if args.skew:
        settle = args.skew + args.settle
        masked = set()
        for i in range(1, len(rst_a)):
            if rst_a[i] != rst_a[i - 1] or rst_a[i] in ("x", "z"):
                masked.update(range(max(0, i - 1), min(len(rst_a), i + settle + 1)))
        masked.update(range(0, settle + 1))
        print(f"  skew {args.skew}: B lags A by {args.skew} cycle(s) "
              f"(declared latency-changing, NOT a strict retiming); "
              f"{len(masked)} reset-transient cycles masked")
        n = len(out_a) - args.skew
        bad = [(i, out_a[i], out_b[i + args.skew])
               for i in range(n)
               if i not in masked and out_a[i] != out_b[i + args.skew]]
        la = [x for i, x in enumerate(out_a[:n]) if i not in masked]
    else:
        bad = [(i, x, y) for i, (x, y) in enumerate(zip(la, lb)) if x != y]
    if bad:
        print(f"RESULT: FAIL  ({len(bad)} mismatching cycles of {len(la)})")
        for i, x, y in bad[:10]:
            print(f"   line {i}:  {args.a}: {x}   |   {args.b}: {y}")
        return 1

    _, ports = parse_module(top_src, top)
    has_rst = any(p["name"] in ("rst_n", "resetn", "reset_n", "arst_n",
                                "rst", "reset", "arst") for p in ports)
    extra = ", incl. mid-run reset pulse" if has_rst else ", no reset port"
    distinct = len(set(out_a))
    if distinct <= 1:
        print(f"RESULT: VACUOUS -- outputs never change across {len(out_a)} "
              f"cycles. The design folds to a constant; the benchmark measures "
              f"nothing even though the variants agree.")
        return 1
    if distinct < max(4, len(out_a) // 100):
        print(f"  NOTE: only {distinct} distinct output values in "
              f"{len(out_a)} cycles. Intentional for the Class G power "
              f"benchmarks; suspicious anywhere else.")

    print(f"RESULT: PASS  ({len(la)} cycles identical{extra}, "
          f"{distinct} distinct output values)")
    if not args.keep:
        subprocess.run(["rm", "-rf", str(tmp)])
    else:
        print(f"  workdir kept: {tmp}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
