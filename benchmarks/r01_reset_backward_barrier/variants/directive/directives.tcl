# r01 directive variant -- Cadence side.
#
# The claim this variant tests: can the *original* RTL reach the retimed result
# if the designer simply turns on the right knobs, with no RTL rewrite?
#
# retime_optimize_reset defaults to FALSE in Genus 23.1, which is precisely why
# the default flow cannot move `q` backward across its synchronous reset.
set_db retime_optimize_reset true
set_db retime_fallback_to_explicit_reset true
set_db retime_effort_level high

# Retiming only runs on designs where it is enabled.
set_db [get_db designs *] .retime true
