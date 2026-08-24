# =============================================================================
# Makefile | ModelSim / Questa   [async_fifo_gray]
# Targets:  sim | gui | do | clean
# Usage:    cd sim/modelsim && make sim
#           cd sim/modelsim && make gui
#           cd sim/modelsim && make do
# =============================================================================
RTL_DIR  = ../../rtl
SIM_DIR  = ..
TOP      = async_fifo_tb

VLOG     = vlog
VSIM     = vsim
VFLAGS   = -timescale "1ns/1ps"

# Auto-discover all RTL + TB sources (no hard-coded filenames)
SOURCES  = $(wildcard $(RTL_DIR)/*.v $(RTL_DIR)/*.sv) \
           $(wildcard $(SIM_DIR)/*.v  $(SIM_DIR)/*.sv)

.PHONY: all sim gui do clean

all: sim

compile:
	@rm -rf work 2>/dev/null || vdel -all -lib work 2>nul || true
	vlib work
	vmap work work
	$(VLOG) $(VFLAGS) $(SOURCES)

sim: compile
	$(VSIM) -c -do "run -all; quit -f" $(TOP)

gui: compile
# 	$(VSIM) -gui -do "do wave.do; run -all; wave zoom full" $(TOP)
	vsim -voptargs=+acc work.$(TOP) -do wave.do -do "run -all"

do:
	$(VSIM) -c -do simulate.do

# Cross-platform clean rule (works in Bash, Zsh, MSYS, Git Bash, and Windows CMD)
clean:
	rm -rf work/ transcript *.wlf wlf* *.log modelsim.ini wave.vcd
	@echo "Cleaned."
