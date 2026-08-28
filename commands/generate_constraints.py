#!/usr/bin/env python3
"""Regenerate every benchmark's SDC and XDC with explicit port lists.

Why explicit: collection helpers differ between tools.  `all_inputs` exists
everywhere but includes the clock, and `remove_from_collection` -- the obvious way
to exclude it -- is not implemented in OpenSTA.  Writing the port names out means
one constraints file is read identically by Genus, Innovus, OpenSTA and Vivado,
which is a precondition for the cross-tool comparison meaning anything.

Ports are read from the benchmark's `orig` variant, and the retimed/directive
variants are required to have identical port lists (the suite checks this).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from benchmark_lib.benchmark import Benchmark
from benchmark_lib.systemverilog_module import parse_module

import os

ROOT = Path(__file__).resolve().parent.parent

CLK_NAMES = {"clk", "clock"}

DRIVE_CELL = os.environ.get("PDK_DRIVING_CELL", "BUF_X4")
DRIVE_PIN = os.environ.get("PDK_DRIVING_PIN", "Z")

def load_meta(benchmark_directory):
    return Benchmark(benchmark_directory).fields

def sdc_text(bid, name, period, max_fanout, clk, ins, outs):
    def plist(ps):
        return " ".join(p["name"] for p in ps)
    drive_cell, drive_pin = DRIVE_CELL, DRIVE_PIN
    return f"""# {bid} -- {name}: ASIC constraints ({os.environ.get("RT_PDK","?")})

if {{![info exists ::CLK_PERIOD]}} {{ set ::CLK_PERIOD {period} }}

create_clock -name clk -period $::CLK_PERIOD [get_ports {clk}]

set_clock_uncertainty [expr {{0.03 * $::CLK_PERIOD}}] [get_clocks clk]
set_clock_transition  [expr {{0.05 * $::CLK_PERIOD}}] [get_clocks clk]

set_input_delay  [expr {{0.15 * $::CLK_PERIOD}}] -clock clk [get_ports {{{plist(ins)}}}]
set_output_delay [expr {{0.15 * $::CLK_PERIOD}}] -clock clk [get_ports {{{plist(outs)}}}]

set_driving_cell -lib_cell {drive_cell} -pin {drive_pin} \\
    [get_ports {{{plist(ins)}}}]
set_load 0.02 [get_ports {{{plist(outs)}}}]

set_max_fanout {max_fanout} [current_design]
"""

def xdc_text(bid, name, period, clk, ins, outs):
    def plist(ps):
        return " ".join(p["name"] + ("[*]" if (p["width"] or 1) > 1 else "")
                        for p in ps)
    return f"""# {bid} -- {name}: Artix-7 constraints
if {{![info exists ::CLK_PERIOD]}} {{ set ::CLK_PERIOD {period} }}

create_clock -name clk -period $::CLK_PERIOD [get_ports {clk}]

set_input_delay  [expr {{0.15 * $::CLK_PERIOD}}] -clock clk [get_ports {{{plist(ins)}}}]
set_output_delay [expr {{0.15 * $::CLK_PERIOD}}] -clock clk [get_ports {{{plist(outs)}}}]
"""

def main():
    n = 0
    for bdir in sorted((ROOT / "benchmarks").iterdir()):
        if not (bdir / "variants" / "orig").is_dir():
            continue
        meta = load_meta(bdir)
        top = meta.get("top")
        srcs = sorted((bdir / "variants" / "orig").glob("*.sv"))
        topsrc = next((s for s in srcs
                       if f"module {top}" in s.read_text()), srcs[0])
        _, ports = parse_module(topsrc, top)

        clk = next((p["name"] for p in ports if p["name"] in CLK_NAMES), None)
        if clk is None:
            print(f"  skip {bdir.name}: no clock port")
            continue
        ins = [p for p in ports if p["dir"] == "input" and p["name"] != clk]
        outs = [p for p in ports if p["dir"] == "output"]

        bid = meta.get("id", bdir.name.split("_")[0])
        nm = meta.get("name", bdir.name)
        pa = meta.get("clock_period_ns", 6.0)
        pf = meta.get("fpga_clock_period_ns", 4.0)
        mf = 64 if "fanout" in bdir.name else 20

        sdc = sdc_text(bid, nm, pa, mf, clk, ins, outs)
        extra = bdir / "constraints" / "extra.sdc.in"
        if extra.exists():
            sdc += "\n# ---- benchmark-specific constraints (constraints/extra.sdc.in) ----\n"
            sdc += extra.read_text()
        (bdir / "constraints" / f"{bid}.sdc").write_text(sdc)
        (bdir / "constraints" / f"{bid}_vivado.xdc").write_text(
            xdc_text(bid, nm, pf, clk, ins, outs))
        n += 1
        print(f"  {bdir.name}: clk={clk} in={len(ins)} out={len(outs)} "
              f"asic={pa}ns fpga={pf}ns")
    print(f"regenerated constraints for {n} benchmarks")

if __name__ == "__main__":
    main()
