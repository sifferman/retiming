#=============================================================================
# Innovus place-and-route for the retiming benchmark suite.
#
# Consumes the Genus netlist + SDC and takes the design to a routed layout, then
# reports the metrics that only exist after placement: routed wirelength,
# congestion, post-route timing, and activity-annotated power.
#
# These are the numbers that matter for the Class G/H benchmarks -- a
# synthesis-only comparison structurally cannot show a wire-delay or congestion
# effect, because the cost function does not exist yet at that stage.
#
# Env:
#   RT_TOP RT_NETLIST RT_SDC RT_OUT RT_LIB RT_TECH_LEF RT_SC_LEF
#   RT_DENSITY   target core utilisation (default 0.55)
#   RT_ASPECT    core aspect ratio (default 1.0)
#   RT_SAIF      optional activity file for power
#=============================================================================


# Innovus report command names vary across releases and some are absent entirely.
# A 20-minute route must not be thrown away because a report command was renamed,
# so every report goes through here.
proc try_report {outfile args} {
  foreach cmd $args {
    if {![catch { uplevel 1 "$cmd > $outfile" }]} { return $cmd }
  }
  set fh [open $outfile w]
  puts $fh "none of the candidate commands were available: $args"
  close $fh
  return "NONE"
}

proc envd {name default} {
  if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
  return $default
}

set top      $::env(RT_TOP)
set netlist  $::env(RT_NETLIST)
set sdc      $::env(RT_SDC)
set out      $::env(RT_OUT)
set lib      $::env(RT_LIB)
set tech_lef $::env(RT_TECH_LEF)
set sc_lef   $::env(RT_SC_LEF)
set density  [envd RT_DENSITY 0.55]
set aspect   [envd RT_ASPECT 1.0]
set saif     [envd RT_SAIF ""]
set rcfile   [envd RT_RC_FILE ""]

file mkdir $out
setMultiCpuUsage -localCpu 4

#--- MMMC setup ----------------------------------------------------------------
# Single nominal corner: the benchmarks are about register placement, not about
# multi-corner closure, and one corner keeps 200+ PnR runs tractable.
create_library_set -name libs_tt -timing [list $lib]
# The gf180 tech LEF carries per-layer RPERSQ/CPERSQDIST, so Innovus can extract
# parasitics directly from LEF -- no captable or QRC tech file needed.  (ORFS's
# setRC.tcl is *not* usable here: `set_layer_rc` is an OpenROAD command.)
# Without real per-layer RC, wirelength would have no delay effect at all, which
# would silently defeat every Class H benchmark.
# WIRE-HOSTILE EMULATION (RT_RC_SCALE), applied on the RC corner.
#
# Measured on gf180 at ~2000 cells: the critical path is 5.9 ns of cell delay and
# 0.03 ns of interconnect -- 0.5% route share. Capping the routing stack raised
# wirelength 8.9% and did not shift that ratio at all, because at this die size the
# absolute RC delay is negligible however far the router detours. Reaching parity
# on gf180 physics would need a net tens of millimetres long, so it is unreachable
# by construction at this scale.
#
# Scaling the extracted RC answers "what if wires were N times worse" -- an
# advanced node, or a die large enough for repeater chains to dominate. This is
# explicitly an EMULATION knob, not gf180 physics, and it is recorded in the
# metrics as rc_scale so no result can quietly depend on it.
set rc_scale [envd RT_RC_SCALE 1]
set rc_args {}
if {$rc_scale != 1} {
  lappend rc_args -preRoute_cap $rc_scale -preRoute_res $rc_scale \
                  -preRoute_clkcap $rc_scale -preRoute_clkres $rc_scale \
                  -postRoute_cap [list $rc_scale $rc_scale $rc_scale] \
                  -postRoute_res [list $rc_scale $rc_scale $rc_scale]
  puts "RT_INFO RC scaled ${rc_scale}x on the RC corner\
 (wire-hostile emulation, NOT gf180 physics)"
}
create_rc_corner   -name rc_nom -T 25 {*}$rc_args
create_delay_corner -name dc_nom -library_set libs_tt -rc_corner rc_nom
create_constraint_mode -name cm_nom -sdc_files [list $sdc]
create_analysis_view -name av_nom -constraint_mode cm_nom -delay_corner dc_nom

set init_lef_file      [list $tech_lef $sc_lef]
set init_verilog       $netlist
set init_top_cell      $top
set init_mmmc_file     ""
set init_design_netlisttype verilog

init_design -setup {av_nom} -hold {av_nom}

# CONGESTION AXIS: cap the routing stack HERE, before placement and CTS.
#
# It has to be set this early. Setting it just before route_opt_design fails with
# NRDB-954 ("invalid option value -route_top_routing_layer ... conflicts with the
# existing routed wires on layer 5") because clock_opt_design has already routed
# the clock tree on Metal4/Metal5 by then, and NanoRoute refuses a cap below wires
# that already exist.
#
# Capping the top is what creates contention -- gf180 has five metals, so Metal3
# roughly halves the signal tracks. Do NOT also set -routeBottomRoutingLayer:
# Metal1 carries PG rails and cell pins, and constraining the bottom fails the
# same way (NRDB-955).
# Layer-name prefix: gf180 uses "Metal", nangate45 "metal".
set mp [envd RT_METAL Metal]
set top_layer [envd RT_MAX_ROUTE_LAYER 5]
if {$top_layer < 5} {
  catch { setNanoRouteMode -routeTopRoutingLayer $top_layer }
  catch { setMaxRouteLayer $top_layer }
  puts "RT_INFO signal routing capped at Metal${top_layer} before CTS (congestion knob)"
} else {
  puts "RT_INFO routing stack unrestricted (up to ${mp}${top_layer})"
}

# WIRE-HOSTILE EMULATION (RT_RC_SCALE).
#
# Measured on gf180 at ~2000 cells: the critical path is 5.9 ns of cell delay and
# 0.03 ns of interconnect -- 0.5% route share. Capping the routing stack raised
# wirelength 8.9% and did NOT move that ratio, because at this die size the
# absolute RC delay is negligible no matter how much the router detours. gf180 at
# this scale simply cannot be net-delay-dominated: reaching parity would need a
# net tens of millimetres long.
#
# So the regime is reached by scaling the extracted RC instead, which answers
# "what if wires were N times worse" -- the situation at an advanced node, or on a
# die large enough that repeater chains dominate. This is explicitly an EMULATION
# knob, not gf180 physics, and any result using it must say so.
# NOTE: the scaling itself is applied on the RC corner above, not here.
# `setRCFactor` exists but reports "setRCFactor is not supported in the MMMC mode"
# and this flow is MMMC, so the call was silently swallowed by its catch and the
# RC-scaled runs came out byte-identical to the baseline. In MMMC the factors
# belong to create_rc_corner.

# LEF-based extraction for pre-route, and the real engine post-route.
setExtractRCMode -engine preRoute
setDelayCalMode -engine aae -SIAware false

#--- floorplan -----------------------------------------------------------------
# Density is a declared per-benchmark constraint, not a tool default: congestion
# behaviour is meaningless unless utilisation is pinned.
# A blockage removes placeable area, so the floorplan has to be sized for it or
# the placer is handed an impossible problem: 0.90 density minus a 30% blockage
# came out at 118.8% utilisation and # ---------------------------------------------------------------------------
# RT_ALT_OPT: everything the tool can do to fix timing WITHOUT retiming.
#
# This exists to test a specific claim -- that retiming is unused in industry because
# "there are usually suboptimal things with timing at other points that can be addressed
# without retiming." Every comparison in this suite so far has been retimed-vs-not at
# the SAME effort, which cannot distinguish "retiming helps" from "retiming helps more
# than the alternatives." Useful skew matters most here: it is retiming's formal dual
# (Fishburn 1990; Sapatnekar & Deokar 1996), so if skew closes the same gap, retiming is
# redundant rather than neglected.
# ---------------------------------------------------------------------------
if {[envd RT_ALT_OPT 0] == 1} {
  puts "RT_INFO alt_opt=on (useful skew + max effort, no retiming)"
  catch { setOptMode -effort high }
  catch { setOptMode -usefulSkew true }
  catch { setOptMode -usefulSkewPostRoute true }
  catch { setOptMode -powerEffort none }
  catch { set_ccopt_property useful_skew true }
  catch { setOptMode -fixFanoutLoad true }
}

place_opt_design refused to run (IMPSP-190).
# Sizing at density*(1-blk) makes the ACHIEVED utilisation land near the requested
# density once the blockage is carved out.
set blk_pre [envd RT_BLOCKAGE 0]
set fp_density $density
if {$blk_pre > 0} {
  set fp_density [expr {$density * (1.0 - $blk_pre)}]
  puts "RT_INFO floorplan sized at $fp_density to leave room for a\
 [expr {$blk_pre*100}]% blockage (target achieved density $density)"
}
floorPlan -site [envd RT_SITE GF018hv5v_green_sc9] \
          -r $aspect $fp_density 6 6 6 6

# Pins spread around the boundary so long cross-die routes are actually possible.
setPinAssignMode -pinEditInBatch true
editPin -side LEFT  -layer 2 -spreadType side -pin [dbGet top.terms.name -v *clk*]
setPinAssignMode -pinEditInBatch false
catch { assignIoPins }

#--- power ---------------------------------------------------------------------
# The Genus netlist carries no supply nets, so VDD/VSS have to be created before
# they can be globally connected to the cells' VDD/VSS LEF pins.
if {[envd RT_DO_PG 1]} {
  addNet -power  VDD
  addNet -ground VSS
  globalNetConnect VDD -type pgpin -pin VDD -all -override
  globalNetConnect VSS -type pgpin -pin VSS -all -override

  # The PG stack must live at or below the signal routing cap. Building rings on
  # Metal3/Metal4 and then capping signals at Metal3 fails with NRDB-954
  # ("conflicts with the existing routed wires on layer 5") -- the router refuses a
  # cap below wires that already exist. So the PG layers are derived from the cap.
  set cap [envd RT_MAX_ROUTE_LAYER 5]
  if {$cap >= 4} {
    set ring_hz ${mp}4 ; set ring_vt ${mp}3 ; set stripe_l ${mp}3
  } else {
    set ring_hz ${mp}3 ; set ring_vt ${mp}2 ; set stripe_l ${mp}2
  }
  puts "RT_INFO PG on ${ring_hz}/${ring_vt} (signal cap Metal${cap})"

  addRing -nets {VDD VSS} -type core_rings -follow core \
          -layer [list top $ring_hz bottom $ring_hz left $ring_vt right $ring_vt] \
          -width 1.2 -spacing 0.8 -offset 0.8
  catch { addStripe -nets {VDD VSS} -layer $stripe_l -direction vertical \
          -width 0.8 -spacing 0.8 -set_to_set_distance 40 -start_from left }
  catch { sroute -connect { corePin floatingStripe } \
          -layerChangeRange [list ${mp}1 $ring_hz] -nets {VDD VSS} }
}

#--- optional placement blockage (congestion axis) -----------------------------
# A central blockage splits the core in two, so logic lands in separate regions and
# every net between them must cross an obstacle. RT_BLOCKAGE is the fraction of
# core width to block, e.g. 0.25.
set blk [envd RT_BLOCKAGE 0]
if {$blk > 0} {
  if {![catch {
    set box [dbGet top.fPlan.coreBox]
    set x1 [lindex $box 0 0]; set y1 [lindex $box 0 1]
    set x2 [lindex $box 0 2]; set y2 [lindex $box 0 3]
    set cw [expr {$x2 - $x1}]; set ch [expr {$y2 - $y1}]
    # Leave generous channels top and bottom. Spanning 8-92% of the height nearly
    # bisected the core and the legalizer could not place 161 instances
    # (IMPSP-2021); 25-75% keeps a routable path around the obstacle.
    createPlaceBlockage -box [list \
        [expr {$x1 + $cw * (0.5 - $blk / 2.0)}] [expr {$y1 + $ch * 0.25}] \
        [expr {$x1 + $cw * (0.5 + $blk / 2.0)}] [expr {$y1 + $ch * 0.75}]]
  } err]} {
    puts "RT_INFO placement blockage across [expr {$blk * 100}]% of core width"
  } else {
    puts "RT_WARN placement blockage failed: $err"
  }
}

#--- place ---------------------------------------------------------------------
setPlaceMode -place_global_place_io_pins true
setDesignMode -process 180
set t0 [clock seconds]
place_opt_design
set t_place [expr {[clock seconds] - $t0}]

try_report $out/congestion_place.rpt "reportCongestion -overflow" "report_congestion -overflow"
catch { timeDesign -preCTS -outDir $out/timing_prects }

#--- clock tree ----------------------------------------------------------------
# place_opt_design leaves the database in PODv2 form, which requires the modern
# iSpatial command set (clock_opt_design / route_opt_design) rather than the
# classic ccopt_design / routeDesign / optDesign trio.
catch { create_clock_tree_spec }
clock_opt_design
set t_cts [expr {[clock seconds] - $t0}]
catch { timeDesign -postCTS -outDir $out/timing_postcts }

#--- route ---------------------------------------------------------------------
# CONGESTION AXIS.
#
# The aim is the regime where NET delay dominates LOGIC delay, which is where a
# wire-blind retimer provably makes the wrong cut. Capping the signal routing stack
# is the most direct way there: gf180 has five metal layers, so restricting signals
# to Metal2-Metal3 roughly halves the available tracks and the router detours
# instead of going straight. It changes no netlist and corrupts no area or cell
# metric -- which is why it is preferable to padding the design with preserved
# filler cells.
#
# Combine with RT_DENSITY (0.85-0.95) and RT_BLOCKAGE to carve the core.
setNanoRouteMode -routeWithTimingDriven true
setNanoRouteMode -routeWithSiDriven false
route_opt_design
setExtractRCMode -engine postRoute
catch { extractRC }
set t_route [expr {[clock seconds] - $t0}]
set t_postroute [expr {[clock seconds] - $t0}]

#--- reports -------------------------------------------------------------------
catch { timeDesign -postRoute -outDir $out/timing_postroute }
try_report $out/congestion_route.rpt "reportCongestion -overflow" "report_congestion -overflow"
try_report $out/gatecount.rpt        reportGateCount report_gate_count
try_report $out/area.rpt             reportDesignArea report_area summaryReport
catch { summaryReport -noHtml -outfile $out/summary.rpt }

# Routed wirelength -- the headline Class H metric.  The dbGet path for this
# moved between releases, so try the known spellings and fall back to parsing
# summaryReport in Python.
set wl NA
foreach q {top.route.totalWireLength top.fPlan.totalWireLength} {
  if {![catch { set v [dbGet $q] }] && $v ne "" && $v ne "0x0"} { set wl $v; break }
}
if {$wl eq "NA"} {
  catch { report_route -summary > $out/route_summary.rpt }
  catch { reportRoute > $out/route_summary.rpt }
}

# Activity-annotated power when a SAIF is available, probabilistic otherwise.
if {$saif ne "" && [file exists $saif]} {
  catch { read_activity_file -format SAIF -scope tb_${top}/dut $saif }
  set pwr_mode saif
} else {
  set pwr_mode probabilistic
}
catch { report_power -outfile $out/power.rpt }

set n_cells 0
set n_seq   0
set area    NA
catch { set n_cells [llength [dbGet top.insts.name]] }
catch { set n_seq   [llength [dbGet -p2 top.insts.cell.isSequential 1]] }
catch { set area    [dbGet top.fPlan.area] }

set fh [open $out/metrics_tcl.json w]
puts $fh "{"
puts $fh "  \"tool\": \"innovus\","
puts $fh "  \"tool_version\": \"[getVersion]\","
puts $fh "  \"top\": \"$top\","
puts $fh "  \"density_target\": $density,"
puts $fh "  \"max_route_layer\": \"$top_layer\","
puts $fh "  \"rc_scale\": \"$rc_scale\","
puts $fh "  \"place_blockage_frac\": \"$blk\","
puts $fh "  \"routed_wirelength_um\": \"$wl\","
puts $fh "  \"num_cells\": $n_cells,"
puts $fh "  \"num_ffs\": $n_seq,"
puts $fh "  \"core_area_um2\": \"$area\","
puts $fh "  \"power_mode\": \"$pwr_mode\","
puts $fh "  \"runtime_place_s\": $t_place,"
puts $fh "  \"runtime_cts_s\": $t_cts,"
puts $fh "  \"runtime_route_s\": $t_route,"
puts $fh "  \"runtime_total_s\": $t_postroute"
puts $fh "}"
close $fh

catch { saveDesign $out/${top}.enc }
catch { defOut -routing $out/${top}.def }
puts "RT_DONE_PNR wl=$wl cells=$n_cells seq=$n_seq time=${t_postroute}s"
exit
