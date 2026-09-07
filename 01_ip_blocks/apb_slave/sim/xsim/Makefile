# =============================================================================
# Makefile | Vivado xsim   [apb_slave_tb]
# Targets:  sim | gui | clean
# Usage:    cd sim/xsim && make sim
#           cd sim/xsim && make gui
# =============================================================================
RTL_DIR  = ../../rtl
SIM_DIR  = ..
TOP      = apb_slave_tb
SNAP     = $(TOP)_snap

XVLOG    = xvlog
XELAB    = xelab
XSIM     = xsim
FLAGS    = --nolog

# Auto-discover all RTL + TB sources (no hard-coded filenames)
SOURCES  = $(wildcard $(RTL_DIR)/*.v $(RTL_DIR)/*.sv) \
           $(wildcard $(SIM_DIR)/*.v  $(SIM_DIR)/*.sv)

.PHONY: all sim gui clean

all: sim

compile:
	$(XVLOG) $(FLAGS) $(SOURCES)
	$(XELAB) $(FLAGS) --timescale 1ns/1ps -debug typical --snapshot $(SNAP) $(TOP)

sim: compile
	$(XSIM) $(FLAGS) $(SNAP) -tclbatch simulate.tcl

gui: compile
	$(XSIM) $(FLAGS) $(SNAP) -gui -tclbatch wave.tcl

# Cross-platform clean rule (works in Bash, Zsh, MSYS, Git Bash, and Windows CMD)
clean:
	rm -rf xsim.dir/ *.pb *.log *.jou *.wdb webtalk/ .Xil/ dfx_runtime.txt vivado*.str wave.vcd 2>/dev/null || true
	@echo "Cleaned."
