# Retiming benchmark suite

28 SystemVerilog benchmarks, each isolating one obstacle to register retiming, with
three variants apiece (original / hand-retimed / directive-only) measured across Genus,
Innovus, Vivado, yosys and OpenROAD on nangate45, Artix-7 and Artix UltraScale+.

## Layout

    benchmarks/     one directory per benchmark: bench.yaml, constraints, three variants
    benchmark_lib/  python library shared by every command
    commands/       executables, one job each
    flows/          tool scripts (tcl) invoked by the runners
    docs/           findings, per-benchmark index, charts
    results/        per-run metrics and the maintained CSVs (nangate45, current)
    archive/        superseded measurements, kept but never pooled with results/

## Reading the results

`results/summary.csv` is the maintained table: one row per benchmark, tool, variant and
mode, all post-route, scored on reg-to-reg total negative slack at a period no
configuration can meet. `results/missing.csv` lists what is unmeasured and whether it
needs a run or a fix. `docs/FINDINGS.md` records what was measured and why the harness
works the way it does.

## What was learned

`docs/FINDINGS.md` records what the tools actually did across 28 benchmarks and five
toolchains, and `papers.md` maps each of those behaviours to the prior work that explains
it. The short version: retiming is decided at synthesis where wire delay is not yet
known, its initial-state problem is hard enough to justify shipping it disabled, and
clock skew scheduling covers much of the same ground more cheaply. Placement-driven
retiming was an active research line from 1998 to 2004 and did not survive into
production flows.

Active work on this direction stopped deliberately. The measurement machinery is the
reusable part: stress-point scoring rather than Fmax, reg-to-reg timing only, and
congestion overflow reported alongside route share so a strangled design is not mistaken
for a fast one.
