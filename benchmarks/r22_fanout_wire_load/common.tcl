# r22 applies to every variant: without this, sequential merging collapses the 16
# clones back into one register and the two variants become the same netlist
# (measured on r05, where the retimed variant reported the same 70 sequential
# cells and identical WNS as orig at every period).
set_db optimize_merge_flops false
