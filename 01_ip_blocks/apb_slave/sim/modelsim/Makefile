#=============================================================================
# Makefile: APB slave / ModelSim or Questa
# Targets: sim | gui | do | clean
#=============================================================================
RTL_DIR = ../../rtl
SIM_DIR = ..
TOP     = apb_slave_tb

VLOG    = vlog
VSIM    = vsim
VFLAGS   = -timescale "1ns/1ps"

# Auto-discover all RTL + TB sources (no hard-coded filenames)
SOURCES  = $(wildcard $(RTL_DIR)/*.v $(RTL_DIR)/*.sv) \
           $(wildcard $(SIM_DIR)/*.v  $(SIM_DIR)/*.sv)

.PHONY: all compile sim gui do clean

all: sim

compile:
	@rm -rf work 2>/dev/null || vdel -all -lib work 2>nul || true
	vlib work
	vmap work work
	$(VLOG) $(VFLAGS) $(SOURCES)

sim: compile
	$(VSIM) -c -do "run -all; quit -f" $(TOP)

gui: compile
	$(VSIM) -voptargs=+acc work.$(TOP) -do wave.do -do "run -all"

do:
	$(VSIM) -c -do simulate.do

clean:
	rm -rf work/ transcript *.wlf wlf* *.log modelsim.ini wave.vcd
	@echo "Cleaned."
