# r19 directive variant -- Cadence side.
#
# Genus has retiming, and Genus has low-power synthesis, but the retimer's cost
# function is delay/area.  There is no attribute that asks it to choose a
# register position to minimise switched capacitance.  This variant turns on
# everything relevant so the negative result is not down to a missed knob.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
set_db retime_optimize_reset true

# Low-power synthesis, such as it is.
catch { set_db lp_insert_clock_gating true }
catch { set_db leakage_power_effort high }
catch { set_db dynamic_power_effort high }
catch { set_db lp_power_analysis_effort high }
