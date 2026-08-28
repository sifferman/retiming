#!/usr/bin/env bash
# Central environment for the retiming benchmark suite.
# Sourced by every flow driver, both locally (donut) and remotely (eq1).

# ---------- where things live ----------
: "${RETIMING_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export RETIMING_ROOT

# Remote host that owns the Cadence + Xilinx licenses.
export EQ_HOST="${EQ_HOST:-eq1-vpn}"

# ---------- ASIC PDK selection ----------
#
# RT_PDK picks the technology. Everything downstream reads the PDK_* variables, so
# switching is one environment variable rather than an edit sweep.
#
# Why nangate45 is the default: measured interconnect RC per unit length is 7710x
# higher than gf180 (gf180 Metal2 5.2e-8 vs nangate45 metal1 4.0e-4 ps/um^2, units
# reconciled -- gf180 liberty is ohm/pF, nangate45 is kohm/fF, both reduce to
# ps/um^2). The wire length at which interconnect costs one gate-delay drops from
# ~62 mm (unreachable on any die) to ~700 um (routine). gf180 at a few thousand
# cells cannot be net-delay-dominated at all, which is the regime this suite exists
# to study. nangate45 is also planar bulk CMOS, so unlike ASAP7 it raises no
# FinFET/academic-license objection from Genus -- verified: 135 cells, 16 flops,
# read clean.
#
# gf180 is kept selectable because the existing Genus/yosys/Vivado results were
# measured on it and must stay reproducible.
export RT_PDK="${RT_PDK:-nangate45}"

export ORFS_PLATFORMS="${ORFS_PLATFORMS:-$HOME/Utils/orfs-2024/flow/platforms}"

case "$RT_PDK" in
  gf180)
    export PDK_DIR="$ORFS_PLATFORMS/gf180"
    export PDK_LIBNAME="gf180mcu_fd_sc_mcu9t5v0"
    export PDK_CORNER_TT="tt_025C_5v00"
    export PDK_CORNER_SS="ss_125C_4v50"
    export PDK_CORNER_FF="ff_n40C_5v50"
    export PDK_LIB_GZ="$PDK_DIR/lib/${PDK_LIBNAME}__${PDK_CORNER_TT}.lib.gz"
    export PDK_LIB_BASENAME="${PDK_LIBNAME}__${PDK_CORNER_TT}.lib"
    export PDK_TECH_LEF="$PDK_DIR/lef/gf180mcu_5LM_1TM_9K_9t_tech.lef"
    export PDK_SC_LEF="$PDK_DIR/lef/gf180mcu_5LM_1TM_9K_9t_sc.lef"
    export PDK_SITE="GF018hv5v_green_sc9"
    export PDK_METAL="Metal"            # layer-name prefix (capitalised here)
    export PDK_MIN_ROUTE_LAYER=2
    export PDK_MAX_ROUTE_LAYER=5
    export PDK_DRIVING_CELL="gf180mcu_fd_sc_mcu9t5v0__buf_4"
    export PDK_DRIVING_PIN="Z"
    export PDK_DONT_USE="*__*_1"        # weakest drive strengths
    export PDK_TIEHI="${PDK_LIBNAME}__tieh"
    export PDK_TIELO="${PDK_LIBNAME}__tiel"
    export PDK_CLKBUFS="${PDK_LIBNAME}__clkbuf_2 ${PDK_LIBNAME}__clkbuf_4 ${PDK_LIBNAME}__clkbuf_8 ${PDK_LIBNAME}__clkbuf_16"
    export PDK_ROOT_CLKBUF="${PDK_LIBNAME}__clkbuf_8"
    export PDK_PG_RING_HZ="Metal4"; export PDK_PG_RING_VT="Metal3"
    ;;
  nangate45)
    export PDK_DIR="$ORFS_PLATFORMS/nangate45"
    export PDK_LIBNAME="NangateOpenCellLibrary"
    export PDK_CORNER_TT="typical"
    export PDK_LIB_GZ=""                # ships uncompressed
    export PDK_LIB_PLAIN="$PDK_DIR/lib/NangateOpenCellLibrary_typical.lib"
    export PDK_LIB_BASENAME="NangateOpenCellLibrary_typical.lib"
    export PDK_TECH_LEF="$PDK_DIR/lef/NangateOpenCellLibrary.tech.lef"
    export PDK_SC_LEF="$PDK_DIR/lef/NangateOpenCellLibrary.macro.mod.lef"
    export PDK_SITE="FreePDK45_38x28_10R_NP_162NW_34O"
    export PDK_METAL="metal"            # lowercase in this platform
    export PDK_MIN_ROUTE_LAYER=2
    export PDK_MAX_ROUTE_LAYER=10
    export PDK_DRIVING_CELL="BUF_X4"
    export PDK_DRIVING_PIN="Z"
    # ORFS excludes these: tap/fill are not logic, and the X1 AOI/OAI211 are
    # pathologically weak.
    export PDK_DONT_USE="TAPCELL_X1 FILLCELL_X1 AOI211_X1 OAI211_X1"
    export PDK_TIEHI="LOGIC1_X1"
    export PDK_TIELO="LOGIC0_X1"
    export PDK_CLKBUFS="CLKBUF_X1 CLKBUF_X2 CLKBUF_X3"
    export PDK_ROOT_CLKBUF="CLKBUF_X3"
    export PDK_PG_RING_HZ="metal4"; export PDK_PG_RING_VT="metal3"
    ;;
  *) echo "env.sh: unknown RT_PDK '$RT_PDK' (expected gf180 or nangate45)" >&2 ;;
esac

export PDK_RC_FILE="$RETIMING_ROOT/flows/openroad/${RT_PDK}_rc.tcl"

# Uncompressed liberty cache (Genus/Innovus/yosys all want a plain .lib)
export LIB_CACHE="${LIB_CACHE:-$RETIMING_ROOT/build/lib_cache}"

# ---------- Xilinx (FPGA) ----------
# Default part. Per-benchmark overrides go in bench.yaml as part_usplus, and
# run_vivado.sh takes a part as its 5th argument the same way run_innovus.sh takes a
# density -- so the part is a knob per run, not a global.
export XILINX_PART="${XILINX_PART:-xc7a100tcsg324-1}"

# ---------- remote tool paths (on eq1) ----------
export CDS_ROOT=/mada/software/cadence
export GENUS_BIN="$CDS_ROOT/DDI231/GENUS231/bin/genus"
export INNOVUS_BIN="$CDS_ROOT/DDI231/INNOVUS231/bin/innovus"
export CONFRML_ROOT="$CDS_ROOT/CONFRML232"
# eq1 has Vivado 2017.4 through 2025.2. The suite's first 456 runs used 2023.1 purely
# because that is what was on PATH, which matters: the "Vivado -retiming is a no-op"
# result was measured on a two-year-old retimer. The version is now explicit, recorded
# per run, and defaults to the newest -- xcau7p does not exist before 2025.2.
export VIVADO_VERSION="${VIVADO_VERSION:-2025.2}"
export VIVADO_BIN="${VIVADO_BIN:-/mada/software/Xilinx/Vivado/$VIVADO_VERSION/bin/vivado}"
export VCS_BIN=/mada/software/synopsys/vcs/P-2019.06-SP2/bin/vcs

# Innovus 23.1 needs RHEL7-era libXp/libicu, side-loaded (no root required).
export EDA_COMPAT_LIBS="$HOME/Utils/eda-compat-libs"
export CDS_SKIP_OS_CHECK_ON_STARTUP=1

# ---------- local (donut) tool paths ----------
export YOSYS_BIN="${YOSYS_BIN:-$HOME/.local/bin/yosys}"
export OPENROAD_BIN="${OPENROAD_BIN:-$RETIMING_ROOT/third_party/install/OpenROAD/bin/openroad}"
export OPENROAD_PREBUILT="$HOME/Utils/openroad-prebuilt/openroad.sh"
export IVERILOG_BIN="${IVERILOG_BIN:-$HOME/Utils/oss-cad-suite/bin/iverilog}"
export VERILATOR_BIN="${VERILATOR_BIN:-$HOME/Utils/oss-cad-suite/bin/verilator}"
export SV2V_BIN="${SV2V_BIN:-$HOME/Utils/zachjs-sv2v/sv2v}"

# ---------- politeness ----------
# Max concurrent heavyweight tool invocations (shared lab box + shared licenses).
# eq1 measured idle (load 1.88, sole user) on 2026-08-23, so the cap is raised from
# 4 -> 8 -> 12. It exists because eq1 is a shared 24-core box on a shared license
# server; if
# anyone else appears, put this back to 4.
export MAX_JOBS="${MAX_JOBS:-12}"
export TOOL_THREADS="${TOOL_THREADS:-4}"

# Resolve a plain (uncompressed) liberty path locally, decompressing into the
# cache only when the platform ships a .gz.
pdk_lib_local() {
  mkdir -p "$LIB_CACHE"
  if [ -n "${PDK_LIB_PLAIN:-}" ] && [ -f "${PDK_LIB_PLAIN}" ]; then
    echo "$PDK_LIB_PLAIN"
  else
    local out="$LIB_CACHE/$PDK_LIB_BASENAME"
    [ -f "$out" ] || gunzip -c "$PDK_LIB_GZ" > "$out"
    echo "$out"
  fi
}
