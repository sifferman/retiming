# r26 directive variant: let the tool retime, and observe what happens to the
# name-based multicycle exception when it does.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
