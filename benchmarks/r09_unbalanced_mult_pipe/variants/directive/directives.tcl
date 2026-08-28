# r09 directive variant -- ask Genus to rebalance the pipeline itself.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
