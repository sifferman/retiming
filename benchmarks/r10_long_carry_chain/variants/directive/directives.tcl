# r10 directive variant. The move needed here ADDS registers, so retiming must be
# allowed to trade area for period rather than minimising register count.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
