# r06 directive variant.  The register to be moved feeds FSM next-state logic, so
# explicitly allow retiming to disturb state points.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
catch { set_db retime_preserve_state_points false }
