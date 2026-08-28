# r02 directive variant -- Cadence side.
#
# retime_fallback_to_explicit_reset is exactly the transform this benchmark needs:
# when no equivalent reset constant exists, unmap reset into logic and retime the
# resulting reset-free register.  It defaults to true; set it explicitly, and turn
# on reset-aware retiming alongside it.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true
set_db retime_fallback_to_explicit_reset true
