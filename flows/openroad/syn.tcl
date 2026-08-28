#=============================================================================
# OpenROAD integrated synthesis (src/syn) for the retiming benchmark suite.
#
# `sv_elaborate` reads SystemVerilog through slang and `synthesize` maps it to
# the technology, loading the result into ODB.
#
# NOTE ON RETIMING: OpenROAD's synthesize has exactly two options,
# -reduce_name_loss and -naming_threshold.  There is NO retiming, and no
# attribute or command that requests it.  This flow therefore has no
# RT_RETIME setting -- the answer to "does OpenROAD's syn do retiming" is no,
# and that is one of the findings this suite records rather than a gap to
# work around.
#
# Env: RT_TOP RT_SRCS RT_SDC RT_OUT RT_LIB RT_TECH_LEF RT_SC_LEF RT_PERIOD RT_VCD
#=============================================================================

proc envd {name default} {
  if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
  return $default
}

set top      $::env(RT_TOP)
set srcs     $::env(RT_SRCS)
set sdc      $::env(RT_SDC)
set out      $::env(RT_OUT)
set lib      $::env(RT_LIB)
set tech_lef $::env(RT_TECH_LEF)
set sc_lef   $::env(RT_SC_LEF)
set period   [envd RT_PERIOD ""]
set vcd      [envd RT_VCD ""]
set rcfile   [envd RT_RC_FILE ""]

file mkdir $out

read_lef $tech_lef
read_lef $sc_lef
read_liberty $lib

set t0 [clock seconds]
sv_elaborate --top $top {*}[split $srcs " "]
set t_elab [expr {[clock seconds] - $t0}]

synthesize
set t_syn [expr {[clock seconds] - $t0}]

if {$period ne ""} { set ::CLK_PERIOD $period }
read_sdc $sdc
if {$rcfile ne "" && [file exists $rcfile]} { source $rcfile }
catch { estimate_parasitics -placement }

set pwr_mode vectorless
if {$vcd ne "" && [file exists $vcd]} {
  if {![catch {read_power_activities -scope tb_${top}/dut -vcd $vcd}]} {
    set pwr_mode vcd
  }
}

catch { report_checks -path_delay max -format full -digits 4 > $out/timing.rpt }
catch { report_worst_slack -max -digits 4 >> $out/timing.rpt }
catch { report_tns -digits 4 >> $out/timing.rpt }
catch { report_design_area > $out/area.rpt }
catch { report_power -digits 5 > $out/power.rpt }
catch { report_cell_usage -file $out/cells.rpt }
catch { write_verilog $out/${top}_netlist.v }

set n_cells 0
catch { set n_cells [llength [get_cells *]] }
set n_seq 0
catch {
  foreach c [get_cells *] {
    if {[string match "*dff*" [get_property $c ref_name]]} { incr n_seq }
  }
}

set fh [open $out/metrics_tcl.json w]
puts $fh "{"
puts $fh "  \"tool\": \"openroad_syn\","
puts $fh "  \"top\": \"$top\","
puts $fh "  \"retime_mode\": \"unsupported\","
puts $fh "  \"num_cells\": $n_cells,"
puts $fh "  \"num_ffs\": $n_seq,"
puts $fh "  \"power_mode\": \"$pwr_mode\","
puts $fh "  \"runtime_elab_s\": $t_elab,"
puts $fh "  \"runtime_total_s\": $t_syn"
puts $fh "}"
close $fh

puts "RT_DONE_ORSYN cells=$n_cells seq=$n_seq time=${t_syn}s"
exit
