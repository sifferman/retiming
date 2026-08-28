# r27 -- exception_scope_probe: ASIC constraints (?)

if {![info exists ::CLK_PERIOD]} { set ::CLK_PERIOD 1.087 }

create_clock -name clk -period $::CLK_PERIOD [get_ports clk]

set_clock_uncertainty [expr {0.03 * $::CLK_PERIOD}] [get_clocks clk]
set_clock_transition  [expr {0.05 * $::CLK_PERIOD}] [get_clocks clk]

set_input_delay  [expr {0.15 * $::CLK_PERIOD}] -clock clk [get_ports {rst_n dina dinb}]
set_output_delay [expr {0.15 * $::CLK_PERIOD}] -clock clk [get_ports {douta doutb}]

set_driving_cell -lib_cell BUF_X4 -pin Z \
    [get_ports {rst_n dina dinb}]
set_load 0.02 [get_ports {douta doutb}]

set_max_fanout 20 [current_design]

# ---- benchmark-specific constraints (constraints/extra.sdc.in) ----
# Pipeline B only: eight rounds cannot close in one cycle, so it gets two.
# Pipeline A is deliberately NOT mentioned anywhere in this file.
set_multicycle_path 2 -setup -from [get_cells bq1_reg*] -to [get_cells bq2_reg*]
set_multicycle_path 1 -hold  -from [get_cells bq1_reg*] -to [get_cells bq2_reg*]
