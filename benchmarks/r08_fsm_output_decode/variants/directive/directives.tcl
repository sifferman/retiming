# r08 directive variant. The register to move is the FSM's output register, so
# state-point preservation must not block it.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
catch { set_db retime_preserve_state_points false }
