# r21 directive variant. Retiming is enabled, but no directive can authorise
# adding a pipeline stage -- that is a latency change, not a retiming.  This
# variant exists to confirm that.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
