# r11 directive variant: ask for maximum retiming effort, since this benchmark is
# specifically about how far the tool is willing to move a register.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
set_db retime_fallback_to_explicit_reset true
