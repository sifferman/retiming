#=============================================================================
# OpenROAD place-and-route for the retiming benchmark suite (gf180mcu 9t 5v0).
#
# Takes a mapped netlist (from yosys, or from OpenROAD's own `synthesize`) to a
# routed layout and reports post-route timing, wirelength, area and power.
#
# Env:
#   RT_TOP RT_NETLIST RT_SDC RT_OUT RT_LIB RT_TECH_LEF RT_SC_LEF RT_RC_FILE
#   RT_DENSITY  target placement density (default 0.55)
#   RT_VCD      optional VCD for activity-annotated power
#
# Every stage is wrapped in `catch` and every metric has a fallback: a routed
# result with one missing report is far more useful than an aborted run, and the
# suite has to survive a few hundred of these.
#=============================================================================

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
set rcfile   [envd RT_RC_FILE ""]
set density  [envd RT_DENSITY 0.55]
set site     [envd RT_SITE GF018hv5v_green_sc9]
set period   [envd RT_PERIOD ""]
set vcd      [envd RT_VCD ""]

file mkdir $out

read_lef $tech_lef
read_lef $sc_lef
read_liberty $lib
read_verilog $netlist
link_design $top

if {$period ne ""} { set ::CLK_PERIOD $period }
read_sdc $sdc

# Per-layer RC.  Without this, wirelength has no delay consequence and every
# physical benchmark in the suite would be measuring nothing.
if {$rcfile ne "" && [file exists $rcfile]} { source $rcfile }

#--- floorplan -----------------------------------------------------------------
initialize_floorplan -site $site -utilization [expr {$density * 100}] \
                     -aspect_ratio 1.0 -core_space 6.0

# Routing tracks are NOT created by initialize_floorplan.  Without them, pin
# placement, global route and detailed route all fail (and OpenROAD segfaults
# rather than erroring cleanly if you get far enough), so this call is mandatory.
# `make_tracks` with no arguments derives the grid from each layer's LEF pitch.
make_tracks

catch { place_pins -hor_layers ${mp}3 -ver_layers ${mp}4 }
catch { insert_tiecells "[envd RT_TIEHI x]/Z" }
catch { insert_tiecells "[envd RT_TIELO x]/[expr {[envd RT_PDK gf180] eq {gf180} ? {ZN} : {Z}}]" }

#--- placement -----------------------------------------------------------------
set t0 [clock seconds]
catch { global_placement -density $density -pad_left 1 -pad_right 1 }
catch { estimate_parasitics -placement }
catch { repair_design }
catch { detailed_placement }
catch { optimize_mirroring }
set t_place [expr {[clock seconds] - $t0}]

#--- clock tree ----------------------------------------------------------------
catch {
  clock_tree_synthesis \
      -buf_list [envd RT_CLKBUFS ""] \
      -root_buf [envd RT_ROOT_CLKBUF ""] \
      -sink_clustering_enable
}
catch { set_propagated_clock [all_clocks] }
catch { estimate_parasitics -placement }
catch { repair_clock_nets }
catch { detailed_placement }
set t_cts [expr {[clock seconds] - $t0}]

#--- routing -------------------------------------------------------------------
# Congestion axis: capping the signal stack is the most direct route to the
# net-delay-dominated regime (see flows/innovus/pnr.tcl for the rationale).
set top_layer [envd RT_MAX_ROUTE_LAYER 5]
set mp [envd RT_METAL Metal]
catch { set_routing_layers -signal ${mp}2-${mp}${top_layer} \
                           -clock ${mp}3-${mp}${top_layer} }
catch { global_route -congestion_report_file $out/congestion.rpt }
catch { estimate_parasitics -global_routing }
set t_groute [expr {[clock seconds] - $t0}]

# Detailed routing is OPTIONAL and off by default.
#
# On gf180mcu, detailed_route on a ~2000-cell design ran past 20 minutes without
# finishing, which does not scale to a 20-benchmark x 3-variant matrix.  The
# physical benchmarks are compared on wirelength and congestion, both of which
# global route provides -- so the default stops there and detailed route is
# opt-in via RT_DETAILED_ROUTE=1.
#
# The trade is explicit rather than silent: a global-route wirelength is an
# estimate and is only ever compared against another global-route number.
set routed global
if {[envd RT_DETAILED_ROUTE 0]} {
  catch { detailed_route -output_drc $out/route.drc -verbose 0 }
  catch { estimate_parasitics -global_routing }
  set routed detailed
}
set t_route [expr {[clock seconds] - $t0}]

#--- activity-annotated power --------------------------------------------------
set pwr_mode vectorless
if {$vcd ne "" && [file exists $vcd]} {
  if {[catch {read_power_activities -scope tb_${top}/dut -vcd $vcd} err]} {
    puts "RT_WARN read_power_activities failed: $err"
  } else {
    set pwr_mode vcd
  }
}

#--- reports -------------------------------------------------------------------
catch { report_checks -path_delay max -format full -digits 4 > $out/timing.rpt }
catch { report_worst_slack -max -digits 4 >> $out/timing.rpt }
catch { report_tns -digits 4 >> $out/timing.rpt }
catch { report_design_area > $out/area.rpt }
catch { report_power -digits 5 > $out/power.rpt }
catch { report_cell_usage -file $out/cells.rpt }
catch { write_def $out/${top}.def }

# Wirelength: report_wire_length requires -net and emits a per-net table, which
# commands/parse_tool_result.py sums.  There is no total-only form.
catch { report_wire_length -net * -file $out/wirelength.rpt }

# Area: report_design_area writes through OpenROAD's logger, which Tcl output
# redirection does not capture, so compute it from ODB directly instead of
# scraping the log.
set cell_area_um2 NA
set core_area_um2 NA
catch {
  set blk [ord::get_db_block]
  set dbu [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
  set a 0.0
  foreach inst [$blk getInsts] {
    set m [$inst getMaster]
    set a [expr {$a + ([$m getWidth] / $dbu) * ([$m getHeight] / $dbu)}]
  }
  set cell_area_um2 [format %.3f $a]
  set core [$blk getCoreArea]
  set core_area_um2 [format %.3f [expr {([$core dx] / $dbu) * ([$core dy] / $dbu)}]]
}

set n_cells 0
set n_seq 0
catch { set n_cells [llength [get_cells *]] }
catch {
  set n_seq 0
  foreach c [get_cells *] {
    if {[get_property $c ref_name] ne "" && \
        [string match "*dff*" [get_property $c ref_name]]} { incr n_seq }
  }
}

set fh [open $out/metrics_tcl.json w]
puts $fh "{"
puts $fh "  \"tool\": \"openroad\","
puts $fh "  \"top\": \"$top\","
puts $fh "  \"density_target\": $density,"
puts $fh "  \"area_um2\": \"$cell_area_um2\","
puts $fh "  \"core_area_um2\": \"$core_area_um2\","
puts $fh "  \"num_cells\": $n_cells,"
puts $fh "  \"num_ffs\": $n_seq,"
puts $fh "  \"power_mode\": \"$pwr_mode\","
puts $fh "  \"route_stage\": \"$routed\","
puts $fh "  \"runtime_place_s\": $t_place,"
puts $fh "  \"runtime_cts_s\": $t_cts,"
puts $fh "  \"runtime_groute_s\": $t_groute,"
puts $fh "  \"runtime_total_s\": $t_route"
puts $fh "}"
close $fh

puts "RT_DONE_ORPNR cells=$n_cells seq=$n_seq time=${t_route}s pwr=$pwr_mode"
exit
