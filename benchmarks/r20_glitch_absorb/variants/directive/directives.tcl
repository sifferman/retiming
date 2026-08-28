# r20 directive variant. Every power-related knob Genus offers is enabled here, to
# establish that none of them expresses "place the register to absorb glitching".
set_db [get_db designs *] .retime true
set_db retime_effort_level high
catch { set_db dynamic_power_effort high }
catch { set_db leakage_power_effort high }
catch { set_db lp_insert_clock_gating true }
