# r17 directive variant -- Cadence side.
#
# On gf180mcu the clock enable becomes a recirculating mux, so the register we
# want moved is inside a mux loop.  Genus has a specific attribute for allowing
# that move; enable it explicitly rather than relying on the default.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
set_db retime_move_mux_loop_with_reg true
