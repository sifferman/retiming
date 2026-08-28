# r05 directive variant -- Cadence side.
#
# Ask the tool to solve the fanout problem on its own: a tight fanout limit plus
# every relevant cloning/retiming knob.  What this variant cannot express is
# *where* the clones should go, which is the whole difficulty -- the right answer
# depends on placement.
set_db [get_db designs *] .retime true
set_db retime_effort_level high
catch { set_db max_fanout 8 }
catch { set_db [get_db designs *] .max_fanout 8 }
