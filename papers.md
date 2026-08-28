# Existing research

Prior work that explains the retiming behaviour measured in this suite. Found by
full-text search over the DAC, ICCAD, DATE and ASPDAC proceedings (~15k papers).

Each section starts with something the commercial tools actually did, then the papers
that account for it. Nearly every surprise in `docs/FINDINGS.md` turns out to be a known
result, which is useful: it means the behaviour is understood, not arbitrary.

## Retiming decided at synthesis cannot see the wires

**Observed.** Genus retimes during synthesis, before any placement exists. Innovus does
not retime at all. On the benchmarks where interconnect dominates, enabling retiming
made total negative slack and wirelength worse rather than better.

This is the known failure mode, and the motivation was stated plainly in 1998:

**`ICCAD/1998/ICCAD98_136.PDF`** — Integrating Logic Retiming and Register Placement.
"In deep sub-micron era, conventional pre-layout retiming cannot work properly because of
dominant interconnection delay that is not available before layout."

**`ICCAD/2001/ICCAD01_0095.PDF`** — Placement Driven Retiming with a Coupled Edge Timing
Model. Asks directly whether predicted retiming gains survive placement.

**`ICCAD/2000/ICCAD00_0002.PDF`** — Physical Planning with Retiming (Cong, Lim). Unifies
partitioning, floorplanning and retiming under a geometric delay model.

**`DAC/2003/DAC03_208.PDF`** — Multilevel Global Placement with Retiming (Cong, Yuan).
Retiming inside global placement, motivated by multicycle interconnect.

**`ICCAD/2004/05C_1.PDF`** — Physical Placement Driven by Sequential Timing Analysis
(Hurst et al.). Post-placement sequential optimisation using skew and register movement.

**`DATE/2003/08D_4.PDF`** — Performance-directed Retiming for FPGAs using Post-placement
Delay Information. Retiming driven by delays measured after placement.

**`DATE/2003/05F_2.PDF`** — Interconnect Planning with Local Area Constrained Retiming
(Lu, Cheng).

Worth noting for anyone picking this up: placement-driven retiming was an active line
from 1998 to 2004 and is absent from today's production ASIC flows. The technique is
understood; its absence is a tooling and methodology question, not an open algorithmic
one.

## Why retiming ships disabled by default

**Observed.** Genus defaults `retime_optimize_reset` to false and design-level `.retime`
to off; Vivado's `-retiming` is off by default on non-Versal parts. Benchmark r32 shows
why one of those defaults exists: after a backward move the register's required reset
value can be provably outside the image of the logic it crossed, so no constant works.

**`ICCAD/1996/ICCAD96_0618.PDF`** — The Case for Retiming with Explicit Reset Circuitry
(Singhal). Adding reset logic when no valid initial state exists — the r32 situation,
and the behaviour behind Genus's `retime_fallback_to_explicit_reset` default.

**`DAC/1995/DAC95_316.PDF`** — The Validity of Retiming Sequential Circuits (Singhal,
Pixley, Rudell). When retiming preserves behaviour, including reset semantics.

**`DAC/1998/DAC98_330.PDF`** — Optimal FPGA Mapping and Retiming with Efficient Initial
State Computation (Cong, Wu).

**`DAC/2008/29.2_Paper.pdf`** — Scalable Min-Register Retiming Under Timing and
Initializability Constraints (Hurst, Mishchenko). Initializability as a first-class
constraint.

Computing an equivalent initial state after retiming is NP-hard in general and sometimes
impossible without adding logic, which is a sufficient explanation for a conservative
default.

## Why the tools duplicate registers, and why that is not free

**Observed.** With retiming enabled, Genus adds registers well beyond the original count
(r30: 1,536 flops becomes substantially more) and wirelength grows with it. On r05,
duplicating the register inside an FSM feedback loop made timing worse than leaving the
design alone, because relieving output fanout loads the loop that sets the period.

**`DAC/2026/520_Duplication-Aware_Retiming_and_Cell_Interface_Redesign_for_Superconductor_Circuit_Minimization.pdf`**
Duplication and retiming as a joint formulation.

**`ICCAD/1998/ICCAD98_402.PDF`** — On the Optimization Power of Retiming and Resynthesis
Transformations. Bounds what the combination can and cannot achieve.

Retiming combined with logic duplication reaches circuit configurations retiming alone
cannot, and duplicating shared nodes across fanout stems is the standard treatment when
reconvergent paths carry differing register counts.

## Clock skew is the cheaper alternative, and complements rather than replaces

**Observed.** The suite never enabled useful skew, so every comparison here is retiming
against a baseline with that knob switched off. Skew is retiming's formal dual and is far
cheaper to deploy, which is part of why retiming sees little use.

**`DAC/1999/DAC99_231.PDF`** — Maximizing Performance by Retiming and Clock Skew
Scheduling (Liu, Papaefthymiou, Friedman). The two are complementary: applying both
beats either alone by more than 21% on over half the benchmarks, under setup and hold
constraints. Skew does not subsume retiming.

**`DAC/2025/1863_A_Fast,_Iterative_Clock_Skew_Scheduling_Algorithm_with_Dyanmic_Sequential_Graph_Extraction.pdf`**
Modern, fast clock skew scheduling.

**`ICCAD/2003/10C_1.PDF`** — Multi-Domain Clock Skew Scheduling, the practical
limited-domain form.

**`ICCAD/2006/01B_2.PDF`** — Optimal Useful Clock Skew Scheduling Under Variations.

**`DAC/2003/DAC03_202.PDF`** — Delay Budgeting in Sequential Circuits with Application to
FPGA Placement.

**`ICCAD/2007/PDFFILES/05C_3.PDF`** — A General Model for Performance Optimization of
Sequential Systems (Bufistov, Cortadella). Unified model covering retiming and recycling.

## Predicting post-route timing before routing

**Observed.** Evaluating one candidate register placement in this suite costs a full
route — 2 to 15 minutes, up to 90 on the large designs. That cost, not the theory, is
what keeps a wire-aware search out of reach.

**`DAC/2023/Restructure-Tolerant_Timing_Prediction_via_Multimodal_Fusion.pdf`** — Predicts
pre-routing timing while modelling the effect of timing optimisation, i.e. a netlist that
changes under the model. The closest published work to what a retiming search would need.

**`DAC/2025/1471_Truly_Pre-Routing_Timing_Prediction_via_Considering_Power_Delivery_Network.pdf`**

**`DAC/2025/1875_GTN-Path_Efficient_Path_Timing_Prediction_through_Waveform_Propagation_with_Graph_Transformer.pdf`**

**`DAC/2026/2333_PBA-rGAT-Edge_Arc-Level_Path-based_Timing_Prediction_with_Scalable_Residual_Edge-Aware_Graph_Attention.pdf`**

**`DAC/2024/Disentangle,_Align_and_Generalize_Learning_A_Timing_Predictor_from_Different_Technology_Nodes.pdf`**

**`DAC/2026/692_DiffDEG_Diffusion-Enhanced_Design_Evolution_Graph_Representation_Learning_for_Post-Layout_Optimization.pdf`**
Represents a design as it evolves across optimisation stages, aimed at post-layout ECO.

Two caveats for anyone building on these. They report accuracy as R2 across a population
of endpoints rather than absolute picoseconds, and a retiming decision can turn on tens
of picoseconds. And they predict for a fixed netlist, whereas retiming changes the
netlist it was conditioned on.

## Automatic pipeline insertion

**Observed.** Several benchmarks need a stage added rather than moved; retiming preserves
register count per cycle by construction and cannot do this.

**`DAC/2024/Revisiting_Automatic_Pipelining_Gate-level_Forwarding_and_Speculation.pdf`**
General stage insertion at gate level, with forwarding and speculation.

Wire pipelining covers the case where the added latency is declared tolerable up front.
The harder problem is the ripple through interface contracts and verification when it is
not.
