# r16 directive variant.  Retiming on, but the pin stays: the question is whether
# Genus still retimes the movable registers when one register in the path is
# preserved, or gives up on the path entirely.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
