# Per-layer RC for FreePDK45 / Nangate Open Cell Library.
#
# Copied from OpenROAD-flow-scripts' nangate45 setRC.tcl (which has no env
# dependencies, unlike the gf180 one) so the suite is self-contained.
#
# These values are why this PDK was chosen: metal1 R*C is 4.0e-4 ps/um^2
# against gf180 Metal2's 5.2e-8 -- 7710x more RC per unit length. A wire
# costs one gate-delay at ~700 um here versus ~62 mm on gf180, which is the
# difference between a reachable and an unreachable net-dominated regime.
# (Liberty units here are fF and kOhm; kOhm*fF = ps, same as gf180's ohm*pF.)

set_layer_rc -layer metal1 -resistance 5.4286e-03 -capacitance 7.41819E-02
set_layer_rc -layer metal2 -resistance 3.5714e-03 -capacitance 6.74606E-02
set_layer_rc -layer metal3 -resistance 3.5714e-03 -capacitance 8.88758E-02
set_layer_rc -layer metal4 -resistance 1.5000e-03 -capacitance 1.07121E-01
set_layer_rc -layer metal5 -resistance 1.5000e-03 -capacitance 1.08964E-01
set_layer_rc -layer metal6 -resistance 1.5000e-03 -capacitance 1.02044E-01
set_layer_rc -layer metal7 -resistance 1.8750e-04 -capacitance 1.10436E-01
set_layer_rc -layer metal8 -resistance 1.8750e-04 -capacitance 9.69714E-02
set_wire_rc -signal -layer metal3
set_wire_rc -clock  -layer metal5
