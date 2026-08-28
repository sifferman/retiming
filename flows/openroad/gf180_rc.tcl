# Per-layer RC for gf180mcu, 5LM_1TM stack, typical corner.
#
# Derived from OpenROAD-flow-scripts' gf180 setRC.tcl, but written out
# self-contained: the ORFS original branches on $::env(METAL_OPTION) and
# $::env(CORNER), which only exist inside an ORFS make invocation.
#
# This file is load-bearing for the whole suite.  The gf180 tech LEF carries a
# single unit RC for every layer, which is enough for a legal route but makes
# wirelength almost delay-free -- and a wirelength that costs no delay would
# silently neutralise every physically-motivated benchmark here.  These are the
# per-layer values ORFS extracted from real gf180 designs.
#
# Via resistance is left at the LEF value (4.5 ohm), which is the typical-corner
# number; ORFS only overrides it for the WC (16.845) and BC (4.23) corners, and
# this suite runs at tt_025C_5v00.

set_layer_rc -layer Metal2 -resistance 3.85861E-04 -capacitance 1.35357E-04
set_layer_rc -layer Metal3 -resistance 2.06673E-04 -capacitance 1.46141E-04
set_layer_rc -layer Metal4 -resistance 1.68609E-04 -capacitance 1.50688E-04
set_layer_rc -layer Metal5 -resistance 7.92778E-05 -capacitance 1.55595E-04

# Estimation layers for pre-route parasitics: signals on Metal2, clocks on Metal4,
# matching the 5-metal branch of the ORFS script.
set_wire_rc -signal -layer Metal2
set_wire_rc -clock  -layer Metal4
