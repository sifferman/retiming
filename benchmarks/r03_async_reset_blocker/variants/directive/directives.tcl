# r03 directive variant -- allow retiming to touch asynchronously reset flops.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
set_db retime_async_reset true
set_db retime_fallback_to_explicit_reset true
