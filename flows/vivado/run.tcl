#=============================================================================
# Vivado synthesis + implementation for the retiming benchmark suite (Artix-7).
#
# Env:
#   RT_TOP RT_SRCS RT_XDC RT_OUT RT_PART RT_PERIOD
#   RT_RETIME   off | on        -> synth_design -retiming
#   RT_DIRECTIVE optional synth directive (e.g. PerformanceOptimized)
#
# Vivado is the tool the project's motivating frustration comes from, so this
# flow deliberately exposes the retiming switch explicitly rather than leaving it
# at whatever the default happens to be.
#=============================================================================

proc envd {name default} {
  if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
  return $default
}

set top     $::env(RT_TOP)
set srcs    $::env(RT_SRCS)
set xdc     $::env(RT_XDC)
set out     $::env(RT_OUT)
set part    [envd RT_PART xc7a100tcsg324-1]
set retime  [envd RT_RETIME on]
set period  [envd RT_PERIOD ""]
set directive [envd RT_DIRECTIVE ""]

file mkdir $out

# The XDC reads ::CLK_PERIOD if the harness set it.
if {$period ne ""} { set ::CLK_PERIOD $period }

create_project -in_memory -part $part
set_property target_language Verilog [current_project]

foreach f [split $srcs " "] {
  if {$f ne ""} { read_verilog -sv $f }
}
read_xdc $xdc

#--- synthesis -----------------------------------------------------------------
set synth_args [list -top $top -part $part]
# The retiming default is FAMILY-DEPENDENT, and the flags are not symmetric:
#
#   non-Versal (7-series, UltraScale, UltraScale+):  retiming OFF by default,
#       enabled with the bare switch `-retiming`.
#   Versal:                                         retiming ON by default,
#       disabled with `-no_retiming`.
#
# So "off" and "on" cannot map to fixed flags -- on Versal, "off" is the one that
# needs a flag. Getting this backwards would silently compare default-on against
# default-on and report that retiming does nothing.
set arch ""
catch { set arch [get_property ARCHITECTURE [get_parts $part]] }
set is_versal [string match -nocase "*versal*" $arch]

switch -- $retime {
  on  { if {!$is_versal} { lappend synth_args -retiming } }
  off { if {$is_versal}  { lappend synth_args -no_retiming } }
  default { error "RT_RETIME must be on|off (got '$retime')" }
}
puts "RT_INFO part=$part arch=$arch versal=$is_versal retime=$retime"
if {$directive ne ""} { lappend synth_args -directive $directive }

set t0 [clock seconds]
puts "RT_INFO synth_design $synth_args"
eval synth_design $synth_args
set t_synth [expr {[clock seconds] - $t0}]

report_utilization -file $out/util_synth.rpt
report_timing_summary -file $out/timing_synth.rpt
write_checkpoint -force $out/post_synth.dcp

# How many registers survived synthesis?
set n_ff_synth [llength [get_cells -hier -filter {IS_SEQUENTIAL}]]

#--- implementation ------------------------------------------------------------
opt_design
place_design
phys_opt_design
route_design
set t_impl [expr {[clock seconds] - $t0}]

report_utilization       -file $out/util_impl.rpt
report_timing_summary    -file $out/timing_impl.rpt
report_route_status      -file $out/route_status.rpt
# -min_congestion_level 1: the default only lists windows above level 5, so every
# report on these designs read "No congestion windows are found above level 5" --
# true, but it yields no number to compare variants with.  Level 1 upward gives the
# actual distribution.
catch { report_design_analysis -congestion -min_congestion_level 1 \
            -file $out/congestion.rpt }
catch { report_utilization -file $out/utilization.rpt }
write_checkpoint -force $out/post_route.dcp

# Vectorless power unless the harness supplies a SAIF.
set saif [envd RT_SAIF ""]
if {$saif ne "" && [file exists $saif]} {
  read_saif -strip_path tb_${top}/dut $saif
  set pwr_mode saif
} else {
  set pwr_mode vectorless
}
report_power -file $out/power.rpt

#--- metrics -------------------------------------------------------------------
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
if {$wns eq ""} { set wns NA }

# Worst slack over paths ENDING AT A REGISTER, reported separately.
#
# Two measurements were wrong before this one, and both are worth recording.
#
# The overall WNS is useless here: on Artix-7 the worst path is
# register-to-output-pad in 104 of 108 runs, and that ~9.4 ns of IOB plus routing
# is identical in the original and the retimed variant. The overall WNS came out
# byte-identical (-5.738 ns) for both, so it could not possibly measure a retiming.
#
# Restricting to register-to-register is also wrong. Several benchmarks (r01 above
# all) are built so the long chain is fed straight from primary inputs -- that is
# the premise of the benchmark. Their critical path is port-to-register, so a
# reg-to-reg-only figure hides the original's real path and makes the retimed
# variant look worse purely because retiming moved work into the reg-to-reg domain
# (measured on r01: orig +1.204 ns vs retimed -3.112 ns, exactly backwards).
#
# `-to [all_registers]` is the right cut: it keeps port-to-register and
# register-to-register paths, which are real logic that retiming can move, and
# drops only register-to-pad, whose delay is a fixed property of the part.
set wns_r2r NA
if {![catch {
      set r2r [get_timing_paths -to [all_registers] -max_paths 1 -nworst 1 -setup]
    }] && [llength $r2r] > 0} {
  set wns_r2r [get_property SLACK $r2r]
  catch { report_timing -to [all_registers] -max_paths 20 \
              -file $out/timing_to_reg.rpt }
}
if {$wns_r2r eq ""} { set wns_r2r NA }
# TNS is parsed out of report_timing_summary by commands/parse_tool_result.py --
# there is no timing_path property for it.

set n_lut 0; set n_ff 0; set n_carry 0
# PRIMITIVE_GROUP == LUT returned 0 on an UltraScale+ part in 2025.2 while the flop
# count came back fine, so fall back to matching the reference name. Counting cells is
# also more reliable than the utilisation report, whose row label differs by family:
# 7-series prints "Slice LUTs", UltraScale+ prints "CLB LUTs".
catch { set n_lut   [llength [get_cells -hier -filter {PRIMITIVE_GROUP == LUT}]] }
if {$n_lut == 0} {
  catch { set n_lut [llength [get_cells -hier -filter {REF_NAME =~ LUT*}]] }
}
catch { set n_ff    [llength [get_cells -hier -filter {IS_SEQUENTIAL}]] }
catch { set n_carry [llength [get_cells -hier -filter {REF_NAME =~ CARRY*}]] }

set fh [open $out/metrics_tcl.json w]
puts $fh "{"
puts $fh "  \"tool\": \"vivado\","
puts $fh "  \"tool_version\": \"[version -short]\","
puts $fh "  \"part\": \"$part\","
puts $fh "  \"architecture\": \"$arch\","
puts $fh "  \"retiming_default_on\": \"$is_versal\","
puts $fh "  \"top\": \"$top\","
puts $fh "  \"retime_mode\": \"$retime\","
puts $fh "  \"directive\": \"$directive\","
puts $fh "  \"wns_ns\": \"$wns\","
puts $fh "  \"wns_reg2reg_ns\": \"$wns_r2r\","
puts $fh "  \"num_lut\": $n_lut,"
puts $fh "  \"num_ff\": $n_ff,"
puts $fh "  \"num_ff_post_synth\": $n_ff_synth,"
puts $fh "  \"num_carry\": $n_carry,"
puts $fh "  \"power_mode\": \"$pwr_mode\","
puts $fh "  \"runtime_synth_s\": $t_synth,"
puts $fh "  \"runtime_total_s\": $t_impl"
puts $fh "}"
close $fh

puts "RT_DONE_VIVADO wns=$wns reg2reg=$wns_r2r lut=$n_lut ff=$n_ff (synth $n_ff_synth) time=${t_impl}s"
exit
