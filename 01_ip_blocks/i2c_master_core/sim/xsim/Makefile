#=============================================================================
# Makefile: i2c_master_core / Vivado xsim
# Targets: sim | gui | clean
# Usage:    cd sim/xsim && make sim
#           cd sim/xsim && make gui
#=============================================================================
RTL_DIR = ../../rtl
SIM_DIR = ..
TOP   = i2c_master_core_tb
SNAP  = $(TOP)_snap

XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

FLAGS = --nolog

.PHONY: all sim gui clean

all: sim

compile:
	$(XVLOG) $(FLAGS) $(RTL_DIR)/i2c_master_core.v $(RTL_DIR)/i2c_master_apb.v \
	                  $(SIM_DIR)/i2c_master_core_tb.v
	$(XELAB) $(FLAGS) --timescale 1ns/1ps -debug typical --snapshot $(SNAP) $(TOP)

sim: compile
	$(XSIM) $(FLAGS) $(SNAP) -tclbatch simulate.tcl

gui: compile
	$(XSIM) $(SNAP) -gui -tclbatch wave.tcl

clean:
	rm -rf xsim.dir/ *.pb *.log *.jou *.wdb webtalk/ .Xil/ dfx_runtime.txt vivado*.str wave.vcd 2>/dev/null || true
	@echo Cleaned.
