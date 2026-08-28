# r18 applies to every variant: this benchmark is specifically about the
# interaction between clock gating and retiming, so the ICG must actually be
# inserted regardless of which variant is being built.
set_db lp_insert_clock_gating true
catch { set_db lp_clock_gating_min_flops 4 }
