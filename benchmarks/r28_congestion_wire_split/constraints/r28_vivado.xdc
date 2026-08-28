# r28 -- congestion_wire_split: Artix-7 constraints
if {![info exists ::CLK_PERIOD]} { set ::CLK_PERIOD 4.0 }

create_clock -name clk -period $::CLK_PERIOD [get_ports clk]

set_input_delay  [expr {0.15 * $::CLK_PERIOD}] -clock clk [get_ports {rst_n din[*]}]
set_output_delay [expr {0.15 * $::CLK_PERIOD}] -clock clk [get_ports {dout[*]}]
