#=============================================================================
# Genus synthesis for the retiming benchmark suite.
#
# Everything is driven by RT_* environment variables so that one script serves
# every benchmark, every variant, and every retiming configuration.
#
#   RT_TOP        top module name
#   RT_SRCS       space-separated SystemVerilog sources
#   RT_SDC        constraints file
#   RT_PERIOD     clock period in ns (overrides the SDC default)
#   RT_OUT        output directory
#   RT_LIB        liberty file (uncompressed)
#   RT_TECH_LEF   technology LEF
#   RT_SC_LEF     standard-cell LEF
#   RT_RETIME     off | on | on_reset   (see below)
#   RT_EXTRA_TCL  optional extra Tcl sourced after constraints (directive variant)
#
# RT_RETIME semantics:
#   off       retiming disabled -- establishes the no-retiming baseline
#   on        retiming enabled with Genus defaults.  NOTE: in Genus 23.1
#             retime_optimize_reset defaults to *false*, so this configuration
#             cannot move a register across a reset boundary.
#   on_reset  retiming enabled *and* retime_optimize_reset/
#             retime_fallback_to_explicit_reset turned on, which is what the
#             Class A benchmarks require.
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
set tech_lef [envd RT_TECH_LEF ""]
set sc_lef   [envd RT_SC_LEF ""]
set retime   [envd RT_RETIME on]
set period   [envd RT_PERIOD ""]
set extra    [envd RT_EXTRA_TCL ""]
set effort   [envd RT_EFFORT high]

file mkdir $out
set_db information_level 7

#--- libraries -----------------------------------------------------------------
read_libs $lib
if {$tech_lef ne "" && $sc_lef ne ""} {
  read_physical -lef [list $tech_lef $sc_lef]
  # Physically-aware synthesis: without this Genus optimises a pure delay graph
  # and cannot see the wire-delay effects that Class H benchmarks are about.
  set_db interconnect_mode ple
}

# Cells the mapper must not pick. Which ones are pathological is PDK-specific --
# gf180's weakest drive strengths (*__*_1), and on nangate45 the tap/fill cells
# plus the X1 AOI/OAI211 that ORFS also excludes -- so the list is passed in
# rather than hardcoded.
foreach pat [split [envd RT_DONT_USE ""] " "] {
  if {$pat eq ""} { continue }
  foreach c [get_db lib_cells $pat] { set_db $c .avoid true }
}

#--- read + elaborate ----------------------------------------------------------
set_db hdl_track_filename_row_col true
set_db hdl_error_on_blackbox true
read_hdl -language sv $srcs
elaborate $top
current_design $top

#--- constraints ---------------------------------------------------------------
if {$period ne ""} { set ::CLK_PERIOD $period }
read_sdc $sdc

set_db syn_generic_effort $effort
set_db syn_map_effort     $effort
set_db syn_opt_effort     $effort

#--- retiming configuration ----------------------------------------------------
set dsn [get_db designs $top]
switch -- $retime {
  off {
    set_db $dsn .retime false
    puts "RT_INFO retime=off"
  }
  on {
    set_db $dsn .retime true
    set_db retime_effort_level high
    puts "RT_INFO retime=on optimize_reset=[get_db retime_optimize_reset]"
  }
  on_reset {
    set_db $dsn .retime true
    set_db retime_effort_level high
    # These two are the crux of the Class A benchmarks.
    set_db retime_optimize_reset true
    set_db retime_fallback_to_explicit_reset true
    set_db retime_async_reset true
    puts "RT_INFO retime=on_reset optimize_reset=[get_db retime_optimize_reset]"
  }
  default { error "RT_RETIME must be off|on|on_reset (got '$retime')" }
}
# Keep the retiming report so we can see what actually moved.
set_db retime_verification_flow true

# Per-benchmark flow settings that must apply to EVERY variant (e.g. enabling
# clock gating for the clock-gated benchmark).  Sourced before the variant's own
# directives so a variant can still override.
set common [envd RT_COMMON_TCL ""]
if {$common ne "" && [file exists $common]} {
  puts "RT_INFO sourcing common tcl: $common"
  source $common
}

if {$extra ne "" && [file exists $extra]} {
  puts "RT_INFO sourcing extra tcl: $extra"
  source $extra
}

#--- how many registers did we start with? -------------------------------------
set n_seq_pre [llength [get_db insts -if {.is_sequential}]]

#--- synthesise ----------------------------------------------------------------
set t0 [clock seconds]
syn_generic
set t_generic [expr {[clock seconds] - $t0}]
syn_map
set t_map [expr {[clock seconds] - $t0}]
syn_opt
set t_opt [expr {[clock seconds] - $t0}]

#--- reports -------------------------------------------------------------------
#--- activity annotation -------------------------------------------------------
# Vectorless power estimation cannot see what the Class G benchmarks are about:
# register switching activity and glitch propagation both depend on real
# stimulus.  When the harness supplies a VCD, annotate from it.
set vcd [envd RT_VCD ""]
set pwr_mode probabilistic
if {$vcd ne "" && [file exists $vcd]} {
  if {[catch {read_vcd -vcd_scope tb_${top}/dut $vcd} err]} {
    puts "RT_WARN read_vcd failed: $err"
  } else {
    set pwr_mode vcd
    puts "RT_INFO annotated activity from $vcd"
  }
}

report_timing  -max_paths 20        > $out/timing.rpt
report_area                         > $out/area.rpt
report_gates                        > $out/gates.rpt
report_power                        > $out/power.rpt
report_qor                          > $out/qor.rpt
catch { report_retime               > $out/retime.rpt }

write_hdl                           > $out/${top}_netlist.v
write_sdc                           > $out/${top}.sdc
catch { write_design -innovus -base_name $out/${top} }

#--- machine-readable summary --------------------------------------------------
# Only genuinely safe attribute lookups happen here.  Slack/power/area are also
# parsed out of the text reports by commands/parse_tool_result.py, which is the
# authority for the results CSV -- Tcl attribute names move between Genus
# releases, report formats do not.

proc safe {script {dflt NA}} {
  if {[catch {uplevel 1 $script} r]} { return $dflt }
  if {$r eq ""} { return $dflt }
  return $r
}

set area    [safe {get_db $dsn .area}]
set n_cells [safe {llength [get_db insts]} 0]
set n_seq   [safe {llength [get_db insts -if {.is_sequential}]} 0]
# get_db .period returns Genus-internal picoseconds, so it reads 1020 for a 1.02 ns
# clock.  The period we requested is authoritative and already in ns; keep the raw
# tool value beside it rather than guessing a scale factor from the library units.
set clkper     $::CLK_PERIOD
set clkper_raw [safe {get_db [get_db clocks] .period}]
set ver     [safe {get_db program_version}]
set optrst  [safe {get_db retime_optimize_reset}]

set fh [open $out/metrics_tcl.json w]
puts $fh "{"
puts $fh "  \"tool\": \"genus\","
puts $fh "  \"tool_version\": \"$ver\","
puts $fh "  \"top\": \"$top\","
puts $fh "  \"retime_mode\": \"$retime\","
puts $fh "  \"retime_optimize_reset\": \"$optrst\","
puts $fh "  \"power_mode\": \"$pwr_mode\","
puts $fh "  \"clock_period_ns\": \"$clkper\","
puts $fh "  \"clock_period_tool_internal\": \"$clkper_raw\","
puts $fh "  \"area_um2\": \"$area\","
puts $fh "  \"num_cells\": $n_cells,"
puts $fh "  \"num_ffs_pre_syn\": $n_seq_pre,"
puts $fh "  \"num_ffs\": $n_seq,"
puts $fh "  \"runtime_generic_s\": $t_generic,"
puts $fh "  \"runtime_map_s\": $t_map,"
puts $fh "  \"runtime_total_s\": $t_opt"
puts $fh "}"
close $fh

puts "RT_DONE area=$area cells=$n_cells seq=$n_seq (was $n_seq_pre) time=${t_opt}s"
exit
