# Retiming Stressor Taxonomy

Each benchmark isolates **one** reason a production retimer leaves performance on the
table. The goal is not "big design, slow clock" — it is "here is a legal, provably
correct register placement that Genus/Vivado did not find, and here is exactly why."

Every benchmark ships a hand-authored reference solution. Unless a benchmark is
explicitly marked `LATENCY-CHANGING`, the reference is a **strict retiming**:
cycle-for-cycle identical I/O behaviour, so the tool was *permitted* to find it.
That distinction is what makes the result a tool failure rather than a spec change.

## Why these axes

Retiming theory is settled for the easy case. Leiserson & Saxe give an exact
polynomial algorithm for minimum-period retiming of a delay graph. Everything hard
about retiming in practice lives in the gap between that graph model and real RTL:

1. **Registers carry reset state.** Backward retiming across a reset flop requires
   computing a new initial state, which may not exist. Touati & Brayton's classic
   answer is to allow only forward moves; Pan showed that is needlessly
   conservative. Commercial tools are conservative here, and it is observable.
2. **Registers have secondary signals.** Clock enable, set/reset, and clock gating
   all have to be replicated coherently when a register moves or is cloned.
3. **The delay graph is not the netlist.** Wire delay, congestion, and fanout load
   are placement-dependent, so a synthesis-time retimer optimises the wrong cost
   function.
4. **Power is not delay.** Flop *output* activity is lower than flop *input*
   activity (Monteiro/Devadas/Ghosh), so register position changes switched
   capacitance even at constant timing. No production tool retimes for this.
5. **Retiming interacts with duplication.** The genuinely optimal move is often
   "clone this register N times and scatter the copies", which is a different
   transform than moving it.

Axes A–B cover (1) and (5), C covers the classical case at scale, D–F cover (2),
G covers (4), H covers (3), and I/J are correctness controls.

---

## Class A — Reset and initial-state barriers

The deepest theoretical obstacle, and the one that matches real Vivado frustration.

| ID | Name | Stressor | Reference solution |
|----|------|----------|--------------------|
| r01 | `reset_backward_barrier` | Critical path terminates at a flop with synchronous reset. The fix is a *backward* move across that flop. A valid new reset value exists and is easy to compute. | Move the register back one logic level; set the new flop's reset value to the pre-image of the old reset value. |
| r02 | `reset_no_valid_init` | Same shape, but no single new reset constant reproduces the old reset behaviour. | Unmap reset into explicit reset circuitry (mux on D), then retime the now-reset-free flop freely. |
| r03 | `async_reset_blocker` | Async reset instead of sync. Blocks control-set remapping entirely. | Convert to sync-reset-equivalent internally, retime, restore async behaviour at the boundary. |
| r04 | `init_only_no_reset` | Flops with an `initial` value and no reset net. Legal to retime on FPGA (INIT attribute travels); ASIC libs have no init concept at all. | Retime freely; propagate INIT. Exposes an FPGA/ASIC asymmetry. |

## Class B — FSM fanout / fanin and register duplication

| ID | Name | Stressor | Reference solution |
|----|------|----------|--------------------|
| r05 | `fsm_high_fanout` | One-hot FSM `state_q` feeds both its own next-state logic and a large combinational fanout cloud. Single register cannot drive both without a load/delay penalty. | Clone `state_q` into N copies, each with the correct reset value, scattered into the cloud; keep the original solely for next-state. |
| r06 | `fsm_high_fanin` | Dual of r05: many status signals converge into next-state logic. | Pre-register partial decodes, then retime the reduction tree. |
| r07 | `fsm_encoding_retime` | Binary-encoded FSM whose decode logic is the critical path. | Retime the decode across the state register; equivalently re-encode plus retime. |
| r08 | `fsm_output_decode` | Mealy output decode, not next-state, is critical. It is a pure feed-forward cone and legally retimable. | Push a register into the output decode cone. Tools wrongly treat it as fused to the FSM. |

## Class C — Classical unbalanced pipelines, at scale

These *should* work. Where they don't, it is an effort/limit problem, not a theory problem.

| ID | Name | Stressor | Reference solution |
|----|------|----------|--------------------|
| r09 | `unbalanced_mult_pipe` | Multiplier partial-product reduction split unevenly across 3 stages. | Rebalance stage boundaries (pure forward retiming). |
| r10 | `long_carry_chain` | Wide ripple-carry with all registers bunched at one end. | Split the chain, register mid-carry. |
| r11 | `deep_retime_distance` | Fix requires moving a register across many logic levels — past typical retiming effort limits. | Move the register the full distance. |
| r12 | `wide_reduction_tree` | 64-input popcount/adder tree, all flops at the output. | Push flops into the tree interior. |

## Class D — Memory and macro boundaries

| ID | Name | Stressor | Reference solution |
|----|------|----------|--------------------|
| r13 | `retime_around_sram` | Logic on both sides of a hard memory. Retiming must respect the macro but can rebalance around it. | Move registers off the address path onto the data path. |
| r14 | `mem_output_reg` | Memory output register placement decides the critical path. | Relocate/absorb the output register. |

## Class E — Hierarchy and preservation conflicts

| ID | Name | Stressor | Reference solution |
|----|------|----------|--------------------|
| r15 | `hier_boundary_block` | Critical path crosses a module boundary; the required move crosses it too. | Move the register across the boundary (requires cross-boundary optimisation). |
| r16 | `dont_touch_conflict` | A preserved register sits mid-path; the correct fix moves its *neighbours*. | Retime around the preserved flop instead of giving up. |

## Class F — Secondary control signals

| ID | Name | Stressor | Reference solution |
|----|------|----------|--------------------|
| r17 | `clock_enable_barrier` | Flops with clock enable. Moving them requires replicating the enable coherently. gf180mcu has *no* enable flop, so this becomes a recirculating mux. | Retime the datapath, replicate the enable term. |
| r18 | `clock_gated_region` | Clock-gated region; retiming must preserve the gating relationship. | Retime inside the gated domain, keeping the enable aligned. |

## Class G — Power-driven retiming (no production tool does this)

| ID | Name | Stressor | Reference solution |
|----|------|----------|--------------------|
| r19 | `power_activity_retime` | Two timing-equivalent register positions with very different switching activity. | Place the register on the low-activity cut. Timing-neutral, power-positive. |
| r20 | `glitch_absorb` | Deep XOR tree glitches propagate into a wide downstream cone. | Register immediately after the XOR tree to absorb glitching. |

## Class H — Physical / congestion-driven retiming (the PhD-shaped axis)

Synthesis-time retimers cannot see these because the cost only exists after placement.

| ID | Name | Stressor | Reference solution |
|----|------|----------|--------------------|
| r21 | `wire_pipeline_cross_die` | Wide bus traverses the die; delay is wire, not logic. | Insert pipeline registers mid-wire (needs placement feedback). |
| r22 | `fanout_wire_load` | Very high fanout net where the load is wire capacitance. | Clone the driving register and co-locate copies with their loads. |
| r23 | `congestion_relief_retime` | A dense reconvergent block routes badly; spreading it with registers reduces congestion. | Retime to spread logic, trading area for routability. |

## Class I — Controls (retiming must NOT help)

Negative controls guard against a tool — or my own tool — "winning" by breaking things.

| ID | Name | Stressor | Expected |
|----|------|----------|----------|
| r24 | `iir_loop_bound` | Feedback loop whose cycle bound is already tight. | No legal retiming improves the period. Any claimed win is a bug. |
| r25 | `c_slow_required` | Only a C-slow transform helps. `LATENCY-CHANGING` — not a legal retiming. | Documented as out-of-scope for strict retiming. |

## Class J — Constraint interaction

These were added after measurement, not planned: they came out of noticing that
Genus refused to retime a benchmark for reasons unrelated to its logic.

| ID | Name | Stressor | Reference solution |
|----|------|----------|--------------------|
| r26 | `sdc_exception_invalidation` | A `set_multicycle_path` naming registers by name freezes exactly those registers. When every register is covered, Genus reports `RETIME-402: does not contain retimeable flops` and the design ends up *worse* than without the constraint. | Recut the pipeline so no exception is needed, and ship an `override.sdc` that removes it. |
| r27 | `exception_scope_probe` | Two independent pipelines; only one is named in an exception. Diagnostic: is the exclusion path-local or design-wide? | Retime only the unconstrained pipeline. **Measured: path-local** — the unnamed pipeline is fully retimed while the named one is untouched. |

A benchmark originally planned here (`reconvergent_paths`) was dropped: analysis
showed that reconvergent fanout imposes no additional retiming constraint beyond
what per-register lag assignment already handles, so it would not have been a
stressor.

## Measured reclassifications

Two benchmarks turned out to be controls rather than challenges, which is a
result worth recording rather than hiding:

- **r01** (`reset_backward_barrier`) — Genus solves it and beats the hand
  reference by 35% (325 MHz vs 240 MHz). It still separates Genus from Vivado,
  which does not retime it at all. Calibration control.
- **r09** (`unbalanced_mult_pipe`) — intended as a positive control, and behaves
  as one: Genus roughly doubles Fmax and beats the reference by 60%.

---

## Reference reading

* C. E. Leiserson, J. B. Saxe. *Retiming Synchronous Circuitry*. Algorithmica, 1991.
* H. Touati, R. Brayton. *Computing the Initial States of Retimed Circuits*. IEEE TCAD, 1993.
* P. Pan. *Optimal Retiming for Initial State Computation*. (`papers/pan_vlsi99.pdf`)
* A. Hurst, A. Mishchenko, R. Brayton. *Fast Minimum-Register Retiming via Binary
  Maximum-Flow*. FMCAD 2007. (`papers/fmcad07_min.pdf`) — the algorithm behind ABC's `retime`.
* J. Monteiro, S. Devadas, A. Ghosh. *Retiming Sequential Circuits for Low Power*. ICCAD 1993.
* N. Shenoy, R. Rudell. *Efficient Implementation of Retiming*. ICCAD 1994.
* S. Malik, E. Sentovich, R. Brayton, A. Sangiovanni-Vincentelli. *Retiming and
  Resynthesis: Optimizing Sequential Networks with Combinational Techniques*.

---

## The congestion axis — reaching net-delay > logic-delay

Every benchmark above can be run in a *congested regime*. This matters because the
interesting failure only exists when net delay is comparable to or larger than logic
delay: that is when the optimal register position stops being "halfway through the
logic" and starts depending on where the wires actually go — which a synthesis-time
retimer cannot know.

The arithmetic is worth stating, because it says exactly how big the prize is. For a
path `reg → A(a levels) → [crossing, delay W] → B(b levels) → reg` with total logic
`L = a + b` fixed:

| retimer | choice | resulting period |
|---|---|---|
| wire-blind (models wires as zero) | `a = b = L/2` | `L/2 + W` |
| wire-aware optimum | `a = b + W` | `(L + W)/2` |

The gap is **W/2**, and it grows with congestion. `r28_congestion_wire_split` is
built so its *original* is the even split a wire-blind tool produces, and its
reference is the asymmetric cut — so the benchmark measures that gap directly.

### Mechanisms, ranked by effect per unit of effort

1. **Cap the signal routing stack** — `RT_MAX_ROUTE_LAYER=3` on a 5-layer gf180
   stack roughly halves the available tracks, so the router detours instead of
   going straight. Costs nothing, changes no netlist, and corrupts no area or cell
   metric. The single best knob.
2. **Raise placement density** — `RT_DENSITY=0.85…0.95`. The placer can no longer
   spread out, so nets lengthen and tracks contend. Already a declared per-benchmark
   constraint.
3. **Non-local connectivity in the RTL** — crossbars, transposes, butterfly/FFT
   strides, multi-read-port register files. This is the *fundamental* generator:
   all-to-all wiring has no locality, so no placement can make it short. It is why
   crossbars are the hard case in real designs.
4. **Central placement blockage** — `RT_BLOCKAGE=0.25…0.40` carves the core so two
   similar-sized clusters must land on opposite sides and every net between them
   crosses. Combined with high density this forces separation without needing
   explicit region constraints.
5. **Low logic depth on a wide bus** — one or two levels between registers makes the
   wire/logic *ratio* large even when absolute wire delay is modest. Cheap way to
   enter the regime without a huge design.
6. **Preserved filler cells** — inserting `dont_touch` cells to inflate the design
   and push logic apart. This does work, and it was the first idea considered, but
   it is the bluntest option: it mostly buys *distance* rather than *routing
   contention*, it inflates the cell and area numbers the suite is simultaneously
   measuring, and it needs the merge/sweep defences that `r05` already showed are
   fragile (`optimize_merge_flops false`). Blockages achieve the separation without
   polluting the metrics, and the layer cap achieves the contention more directly.
   Kept as a fallback, not the primary tool.

### Reading the result

The measurement that says whether the regime was reached is the **logic vs route
split** in the post-route timing report — Innovus prints
`Data Path Delay: X (logic Y% route Z%)`. Below ~50% route the benchmark is still
logic-dominated and the wire-aware optimum barely differs from the wire-blind one;
above it, the asymmetric cut should start winning.
