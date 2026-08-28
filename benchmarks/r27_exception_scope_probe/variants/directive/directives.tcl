# r27 directive variant: retiming fully enabled.  The question is whether
# pipeline A gets retimed despite pipeline B carrying a timing exception.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
