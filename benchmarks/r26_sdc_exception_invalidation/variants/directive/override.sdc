# r26 directive variant -- IDENTICAL RTL to orig, constraints without the
# name-based multicycle exception.
#
# This is the controlled experiment: if orig (with the exception) refuses to
# retime and this (without it) retimes, then the exception itself is what
# disabled retiming.
#
# The reference recut the pipeline 5/6 instead of 3/8, so stage 2 closes in a
# single cycle and the multicycle exception is no longer needed.  It is REMOVED
# rather than left in place pointing at names that no longer exist.
#
# That is the part a retiming tool has to do and currently does not: rewriting the
# netlist without rewriting the constraints that describe it leaves the design in a
# state nobody signed off on.

if {![info exists ::CLK_PERIOD]} { set ::CLK_PERIOD 4.0 }

create_clock -name clk -period $::CLK_PERIOD [get_ports clk]
set_clock_uncertainty 0.10 [get_clocks clk]
set_clock_transition  0.10 [get_clocks clk]

set_input_delay  0.30 -clock clk [get_ports {rst_n din}]
set_output_delay 0.30 -clock clk [get_ports {dout}]

set_driving_cell -lib_cell gf180mcu_fd_sc_mcu9t5v0__buf_4 -pin Z \
    [get_ports {rst_n din}]
set_load 0.02 [get_ports {dout}]

set_max_fanout 20 [current_design]

# No multicycle exception -- deliberately removed to isolate its effect.
