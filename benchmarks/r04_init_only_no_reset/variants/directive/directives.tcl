# r04 directive variant. With no reset semantics on the ASIC side, retiming has
# no initial-state constraint to respect at all.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
