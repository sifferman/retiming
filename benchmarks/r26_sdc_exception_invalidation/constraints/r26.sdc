# r26 -- sdc_exception_invalidation: ASIC constraints (?)

if {![info exists ::CLK_PERIOD]} { set ::CLK_PERIOD 0.734 }

create_clock -name clk -period $::CLK_PERIOD [get_ports clk]

set_clock_uncertainty [expr {0.03 * $::CLK_PERIOD}] [get_clocks clk]
set_clock_transition  [expr {0.05 * $::CLK_PERIOD}] [get_clocks clk]

set_input_delay  [expr {0.15 * $::CLK_PERIOD}] -clock clk [get_ports {rst_n din}]
set_output_delay [expr {0.15 * $::CLK_PERIOD}] -clock clk [get_ports {dout}]

set_driving_cell -lib_cell BUF_X4 -pin Z \
    [get_ports {rst_n din}]
set_load 0.02 [get_ports {dout}]

set_max_fanout 20 [current_design]

# ---- benchmark-specific constraints (constraints/extra.sdc.in) ----
# The designer's intent for stage 2, expressed as a constraint rather than in RTL.
#
# Stage 2 is eight rounds deep and cannot close in one cycle at this period, so it
# is given two.  This is completely ordinary practice -- and it can only be written
# by naming the registers involved:
set_multicycle_path 2 -setup -from [get_cells fq1_reg*] -to [get_cells fq2_reg*]
set_multicycle_path 1 -hold  -from [get_cells fq1_reg*] -to [get_cells fq2_reg*]

# Which is precisely the problem.  A retimer that relocates and renames these
# registers leaves this exception matching nothing, and the two cycles of relief
# disappear without the netlist ever looking wrong.
