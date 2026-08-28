# r28 directive variant: retiming at full effort, physically aware.
# The question is whether a synthesis-time retimer can find an ASYMMETRIC cut
# whose optimality depends on a post-placement wire delay it cannot yet see.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
catch { set_db interconnect_mode ple }
