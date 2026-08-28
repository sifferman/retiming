# r05 applies to EVERY variant, so the flow settings stay symmetric and only the
# RTL differs between variants.
#
# Why this is here: the reference solution for r05 is eight clones of the state
# register with identical D inputs and identical reset values.  To Genus those are
# eight copies of the same flop, and sequential merging collapses them straight
# back into one.  Measured: the retimed variant came out with exactly 70
# sequential cells -- the same as orig -- and bit-identical WNS at every period in
# the sweep.  The benchmark was measuring the same netlist twice without saying so.
#
# The RTL attributes (dont_touch / preserve / syn_preserve on rep_q) do NOT prevent
# this, and `set_db <inst> .preserve true` cannot be applied before mapping
# ("Cannot preserve unmapped leaf instance", TUI-210).  Disabling flop merging is
# the setting that actually holds, and putting it in common.tcl means orig and
# retimed are synthesised under identical conditions.
#
# This is itself part of the finding: the tools' own optimiser actively undoes
# deliberate register duplication, so any real retiming tool must both make the
# placement-aware cloning decision and defend it downstream.
set_db optimize_merge_flops false
