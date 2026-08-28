# r20 -- glitch_absorb: ASIC constraints (?)

if {![info exists ::CLK_PERIOD]} { set ::CLK_PERIOD 0.59 }

create_clock -name clk -period $::CLK_PERIOD [get_ports clk]

set_clock_uncertainty [expr {0.03 * $::CLK_PERIOD}] [get_clocks clk]
set_clock_transition  [expr {0.05 * $::CLK_PERIOD}] [get_clocks clk]

set_input_delay  [expr {0.15 * $::CLK_PERIOD}] -clock clk [get_ports {rst_n din}]
set_output_delay [expr {0.15 * $::CLK_PERIOD}] -clock clk [get_ports {dout}]

set_driving_cell -lib_cell BUF_X4 -pin Z \
    [get_ports {rst_n din}]
set_load 0.02 [get_ports {dout}]

set_max_fanout 20 [current_design]
