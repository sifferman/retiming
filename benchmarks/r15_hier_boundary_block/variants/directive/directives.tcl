# r15 directive variant.  The move crosses a module boundary, so boundary
# optimisation has to be on for the tool to have any chance.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
catch { set_db auto_ungroup both }
catch { set_db boundary_opto true }
