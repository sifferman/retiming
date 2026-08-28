#!/usr/bin/env python3
"""Create the non-RTL scaffolding for a benchmark: SDC, XDC and bench.yaml.

RTL is always hand-written -- each benchmark is a bespoke structure and the whole
value is in that structure.  Everything around it is boilerplate and lives here
so 25+ benchmarks stay consistent in how they are constrained and measured.
"""

from pathlib import Path

import argparse

ROOT = Path(__file__).resolve().parent.parent

SDC = """# {bid} -- {name}: ASIC constraints (gf180mcu 9t 5v0)

if {{![info exists ::CLK_PERIOD]}} {{ set ::CLK_PERIOD {period_asic} }}

create_clock -name clk -period $::CLK_PERIOD [get_ports {clk_port}]
set_clock_uncertainty 0.10 [get_clocks clk]
set_clock_transition  0.10 [get_clocks clk]

set_input_delay  0.30 -clock clk [remove_from_collection [all_inputs] [get_ports {clk_port}]]
set_output_delay 0.30 -clock clk [all_outputs]

set_driving_cell -lib_cell gf180mcu_fd_sc_mcu9t5v0__buf_4 -pin Z \\
    [remove_from_collection [all_inputs] [get_ports {clk_port}]]
set_load 0.02 [all_outputs]

set_max_fanout {max_fanout} [current_design]
"""

XDC = """# {bid} -- {name}: Artix-7 constraints
if {{![info exists ::CLK_PERIOD]}} {{ set ::CLK_PERIOD {period_fpga} }}

create_clock -name clk -period $::CLK_PERIOD [get_ports {clk_port}]
set_input_delay  0.30 -clock clk [filter [all_inputs] {{NAME !~ "*{clk_port}*"}}]
set_output_delay 0.30 -clock clk [all_outputs]
"""

YAML = """id: {bid}
name: {name}
class: "{cls}"
top: {top}
latency_preserving: {latency}
density_target: {density}

description: |
{desc}

constraints:
  asic:
    clock_period_ns: {period_asic}
    core_density: {density}
    input_delay_ns: 0.30
    output_delay_ns: 0.30
    max_fanout: {max_fanout}
    library: gf180mcu_fd_sc_mcu9t5v0 (tt_025C_5v00)
  fpga:
    clock_period_ns: {period_fpga}
    part: xc7a100tcsg324-1

variants:
  orig:      variants/orig
  retimed:   variants/retimed
  directive: variants/directive

primary_metric: {metric}
expected: |
{expected}
"""

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--top", required=True)
    ap.add_argument("--cls", required=True)
    ap.add_argument("--period-asic", type=float, default=6.0)
    ap.add_argument("--period-fpga", type=float, default=4.0)
    ap.add_argument("--density", type=float, default=0.55)
    ap.add_argument("--max-fanout", type=int, default=20)
    ap.add_argument("--clk-port", default="clk")
    ap.add_argument("--latency", default="true")
    ap.add_argument("--metric", default="fmax")
    ap.add_argument("--desc", default="")
    ap.add_argument("--expected", default="")
    a = ap.parse_args()

    bdir = ROOT / "benchmarks" / f"{a.id}_{a.name}"
    for sub in ("variants/orig", "variants/retimed", "variants/directive",
                "constraints", "tb"):
        (bdir / sub).mkdir(parents=True, exist_ok=True)

    def indent(t):
        return "\n".join("  " + ln for ln in (t or "TBD").strip().splitlines())

    kw = dict(bid=a.id, name=a.name, top=a.top, cls=a.cls,
              period_asic=a.period_asic, period_fpga=a.period_fpga,
              density=a.density, max_fanout=a.max_fanout, clk_port=a.clk_port,
              latency=a.latency, metric=a.metric,
              desc=indent(a.desc), expected=indent(a.expected))

    (bdir / "constraints" / f"{a.id}.sdc").write_text(SDC.format(**kw))
    (bdir / "constraints" / f"{a.id}_vivado.xdc").write_text(XDC.format(**kw))
    (bdir / "bench.yaml").write_text(YAML.format(**kw))
    print(f"scaffolded {bdir.relative_to(ROOT)}")

if __name__ == "__main__":
    main()
