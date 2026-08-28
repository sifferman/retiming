#!/usr/bin/env python3
"""Generate r29_wide_crossing: the movable-crossing benchmark at ~10k cells.

WHY A GENERATOR RATHER THAN HAND-WRITTEN RTL
The three variants differ only in WHERE the register sits relative to the crossing,
but moving it changes the register's RESET VALUE -- the retimed mid-register holds
the state of a later pipeline point, so its reset value is the original reset value
pushed through the rounds that moved behind it. That is the Touati-Brayton
initial-state problem, and getting it wrong makes the variants inequivalent in the
first cycles after reset (which commands/check_equivalence_by_simulation.py does catch, having caught it
before). Computing those constants here and emitting them as literals means the
equivalence does not depend on a tool folding a constant function at elaboration,
which iverilog and Genus do not agree about.

SIZING -- why these numbers
r22 already reaches 12.6k cells and 15.3% route share unaided, so size alone is not
what is missing; what is missing is r28's movable-crossing structure AT that size.
r28 has the right structure but only ~800 cells, so its die is tens of microns
across and the crossing cannot cost real delay -- it needed a Metal3 cap, a blockage
and a 4:1 core to reach 15% route share, and returned only 18 ps.

  bus width      512 bits    a genuinely wide crossing, and the source of cell count
  rounds         8           each round is AND-of-two-rotations then XOR: 2 gate
                             levels and 2 cells per bit, so ~1024 cells per round
  combinational  ~8200 cells 8 rounds x 512 bits x 2
  registers      1536 flops  3 stages x 512
                 ---------
  total          ~9.7k cells

Per-side logic delay at the even split is 4 rounds = 8 gate levels, roughly 0.32 ns
in nangate45. That is the point: it puts the crossing delay W and the per-side logic
delay in the same range, which is the regime where the asymmetric cut pays.

  orig     4 rounds | crossing | 4 rounds   period = max(4r, W + 4r) = W + 4r
  retimed  6 rounds | crossing | 2 rounds   period = max(6r, W + 2r)

With r ~ 0.08 ns and W ~ 0.32 ns: orig 0.64 ns, retimed 0.48 ns -- a 25% win, and
exactly the W/2 the theory predicts. The benchmark only rewards the asymmetric cut
once W exceeds about 2 rounds, so the measured W is what decides whether this
benchmark says anything; that gets checked after the first route.

NON-COLLAPSIBLE ROUNDS
Two earlier benchmarks in this suite were dead because their logic reduced: r12's 64
summands collapsed to 8 variables, and r19's complementary XOR masks made a popcount
identically 32. Rounds here are (x ^ C) ^ (rotl(x,1) & rotl(x,k)): the AND makes each
round nonlinear, so composing them raises algebraic degree instead of cancelling, and
per-round distinct constants and rotations stop common-subexpression elimination from
sharing work between rounds.
"""

from pathlib import Path

import argparse

ROOT = Path(__file__).resolve().parent.parent
W = 1024
ROUNDS = 8
SPLIT_ORIG = 4      # the even split a wire-blind retimer produces
SPLIT_RETIMED = 5   # one round moved ahead of the register: threshold is r, not 2r
MASK = (1 << W) - 1

CONSTS = [0xA5, 0x3C, 0x5A, 0xC3, 0x69, 0x96, 0xF0, 0x0F]
ROTS = [3, 5, 7, 11, 13, 17, 19, 23]
START = int(("5A" * (W // 8)), 16)      # mid-register reset value in the orig cut

def rotl(x, n):
    n %= W
    return ((x << n) | (x >> (W - n))) & MASK

def apply_round(x, i):
    c = int(str(f"{CONSTS[i]:02X}") * (W // 8), 16)
    return ((x ^ c) ^ (rotl(x, 1) & rotl(x, ROTS[i]))) & MASK

def compute_middle_register_reset(split):
    """Reset value of the mid register for a given cut.

    The orig cut's mid register holds the state after SPLIT_ORIG rounds, and START is
    defined to be that value. A cut that moves the register LATER must hold the same
    value pushed through the rounds it moved past, or the two variants disagree for
    the first cycles after every reset.
    """
    x = START
    for i in range(SPLIT_ORIG, split):
        x = apply_round(x, i)
    return x

def sv(split, label, note):
    def chain(expr, lo, hi):
        for i in range(lo, hi):
            expr = f"rnd_{i}({expr})"
        return expr
    chain_a = chain("in_q", 0, split)
    chain_b = chain("bus", split, ROUNDS)
    fns = []
    for i in range(ROUNDS):
        c = f"{CONSTS[i]:02X}" * (W // 8)
        fns.append(
            f"  // round {i}: nonlinear (AND of two rotations), 2 gate levels/bit\n"
            f"  function automatic logic [W-1:0] rnd_{i} (input logic [W-1:0] x);\n"
            f"    rnd_{i} = (x ^ {W}'h{c}) ^ (rotl1(x) & rotl{ROTS[i]}(x));\n"
            f"  endfunction")
    rots = []
    for r in sorted(set(ROTS + [1])):
        rots.append(
            f"  function automatic logic [W-1:0] rotl{r} (input logic [W-1:0] x);\n"
            f"    rotl{r} = (x << {r}) | (x >> (W - {r}));\n"
            f"  endfunction")
    return f"""// r29 -- wide_crossing  ({label})
//
//   (in_q) -[{split} rounds]-> (mid_q) ==== {W}-bit crossing ====> [{ROUNDS - split} rounds] -> (out_q)
//
{note}
//
// GENERATED by commands/generate_wide_crossing_benchmark.py -- edit that, not this file. The mid-register
// reset value below is computed there, because moving the register past a round
// changes the value it must reset to.

module r29_wide_crossing (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [63:0]  din,
    output logic [63:0]  dout
);
  // PORTS ARE NARROW ON PURPOSE. Exposing the whole {W}-bit crossing at the top level
  // asked Innovus to spread 2049 pins around a die with 1756 free tracks, which fails
  // outright (IMPPTN-970) -- and it was never realistic: real designs carry wide buses
  // internally and present narrow interfaces. The crossing is still {W} bits wide
  // where it matters, between the two clusters.
  localparam int W = {W};
  localparam logic [W-1:0] MID_RESET = {W}'h{compute_middle_register_reset(split):0{W // 4}X};

{chr(10).join(rots)}

{chr(10).join(fns)}

  logic [W-1:0] in_q, mid_q, out_q, bus, a_out, b_out;

  // Expand 64 -> W with a distinct constant per 64-bit slice, so the slices are not
  // copies of each other and synthesis cannot share the logic between them.
  logic [W-1:0] wide_in;
  always_comb
    for (int s = 0; s < W/64; s++)
      wide_in[s*64 +: 64] = din ^ (64'h9E3779B97F4A7C15 * unsigned'(s + 1));

  always_ff @(posedge clk) begin
    if (!rst_n) in_q <= '0;
    else        in_q <= wide_in;
  end

  // ---- cluster A: {split} of {ROUNDS} rounds -------------------------------------
  always_comb a_out = {chain_a};

  always_ff @(posedge clk) begin
    if (!rst_n) mid_q <= MID_RESET;
    else        mid_q <= a_out;
  end

  // THE CROSSING. Pure wire: {W} bits from cluster A to cluster B.
  always_comb bus = mid_q;

  // ---- cluster B: the remaining {ROUNDS - split} rounds ---------------------------
  always_comb b_out = {chain_b};

  always_ff @(posedge clk) begin
    if (!rst_n) out_q <= '0;
    else        out_q <= b_out;
  end

  // Reduce W -> 64 by XOR-folding, which keeps every internal bit observable at the
  // output (needed for the equivalence check to have any power) without adding ports.
  always_comb begin
    dout = 64'h0;
    for (int s = 0; s < W/64; s++)
      dout = dout ^ out_q[s*64 +: 64];
  end

endmodule
"""

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="benchmarks/r29_wide_crossing")
    args = ap.parse_args()
    base = ROOT / args.out
    specs = [
        ("orig", SPLIT_ORIG, "the wire-blind cut",
         "// This is the EVEN split, which is what a retimer that models wires as zero\n"
         "// delay produces: it balances logic depth and stops. Real period is then\n"
         "// max(a, W + b) = W + 4r, because the crossing sits in cluster B's cycle."),
        ("retimed", SPLIT_RETIMED, "the wire-aware cut",
         "// ASYMMETRIC on purpose. With the crossing costing W, the two cycles are a\n"
         "// and W + b, so the balance point is a = b + W rather than a = b. Moving two\n"
         "// rounds ahead of the register shortens the crossing's cycle at the cost of\n"
         "// lengthening the other, and the period drops by about W/2."),
        ("directive", SPLIT_ORIG, "the wire-blind cut + tool directives",
         "// Same RTL as orig. The retiming is asked for through directives.tcl instead\n"
         "// of by rewriting, so the two mechanisms can be compared."),
    ]
    for name, split, label, note in specs:
        d = base / "variants" / name
        d.mkdir(parents=True, exist_ok=True)
        (d / "r29_wide_crossing.sv").write_text(sv(split, label, note))
        print(f"  wrote {d}/r29_wide_crossing.sv  (split {split}/{ROUNDS - split})")
    print(f"\n  mid-register reset, orig cut    = {compute_middle_register_reset(SPLIT_ORIG):#x}"[:78])
    print(f"  mid-register reset, retimed cut = {compute_middle_register_reset(SPLIT_RETIMED):#x}"[:78])
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
