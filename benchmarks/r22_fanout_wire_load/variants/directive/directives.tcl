# r22 directive variant: ask the tool to solve the fanout itself.  What a
# fanout limit cannot express is WHERE the copies should go, which is the
# whole difficulty -- the right answer depends on placement.
catch { set_db max_fanout 16 }
catch { set_db [get_db designs *] .max_fanout 16 }
